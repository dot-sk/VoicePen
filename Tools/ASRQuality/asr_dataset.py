"""Private dictation corpus preparation, manual review, and confirmed export."""

import argparse
import array
from collections import Counter
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import struct
import sys
import tempfile
from urllib.parse import urlsplit
import wave
import zlib


REPOSITORY = Path(__file__).resolve().parents[2]
DEFAULT_DATA = REPOSITORY / ".local/asr-quality"
DEFAULT_DATABASE = Path.home() / "Library/Application Support/VoicePen/VoicePen.sqlite"


class DatasetError(ValueError):
    pass


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def fingerprint(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".save-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def wav_contents(path):
    data = Path(path).read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise DatasetError("Expected a RIFF WAV recording")
    position, format_data, pcm = 12, None, None
    while position + 8 <= len(data):
        tag, length = struct.unpack_from("<4sI", data, position)
        payload = data[position + 8:position + 8 + length]
        if len(payload) != length:
            raise DatasetError("Incomplete WAV chunk")
        if tag == b"fmt ":
            format_data = payload
        elif tag == b"data":
            pcm = payload
        position += 8 + length + length % 2
    if format_data is None or len(format_data) < 16 or pcm is None:
        raise DatasetError("Missing WAV format or samples")
    encoding, channels, rate, _, alignment, bits = struct.unpack_from("<HHIIHH", format_data)
    if encoding == 65534 and len(format_data) >= 40:
        encoding = struct.unpack_from("<H", format_data, 24)[0]
    if channels < 1 or rate < 1 or alignment < 1 or len(pcm) % alignment:
        raise DatasetError("Invalid WAV frame layout")
    if (encoding, bits) not in ((1, 16), (3, 32)):
        raise DatasetError("Review supports PCM16 or Float32 WAV recordings")
    return {"channels": channels, "sample_rate": rate, "frames": len(pcm) // alignment,
            "duration": len(pcm) / alignment / rate, "encoding": encoding, "bits": bits}, pcm


def playback_copy(source, destination):
    info, pcm = wav_contents(source)
    if info["encoding"] == 3:
        floats = array.array("f")
        floats.frombytes(pcm)
        if sys.byteorder != "little":
            floats.byteswap()
        samples = array.array("h", (round(max(-1, min(1, value)) * 32767)
                                   if math.isfinite(value) else 0 for value in floats))
        if sys.byteorder != "little":
            samples.byteswap()
        pcm = samples.tobytes()
    with wave.open(str(destination), "wb") as output:
        output.setparams((info["channels"], 2, info["sample_rate"], 0, "NONE", "not compressed"))
        output.writeframes(pcm)
    return info


def create_dataset(candidates, destination, context):
    destination = Path(destination).resolve()
    if destination.exists():
        raise DatasetError("Destination already exists; review work will not be overwritten")
    if not candidates:
        raise DatasetError("No available recordings with draft text")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".asr-import-", dir=destination.parent))
    try:
        (staging / "audio").mkdir()
        (staging / "playback").mkdir()
        entries, references = [], {}
        for index, candidate in enumerate(candidates, 1):
            sample_id = f"sample-{index:03}"
            source = Path(candidate["source_path"])
            original = staging / f"audio/{sample_id}.wav"
            shutil.copyfile(source, original)
            info = playback_copy(original, staging / f"playback/{sample_id}.wav")
            entry = {"id": sample_id, "audio": f"audio/{sample_id}.wav", "sha256": fingerprint(original),
                     "duration": info["duration"], "sample_rate": info["sample_rate"], "frames": info["frames"],
                     "draft_text": candidate["draft_text"], "source_id": candidate["source_id"],
                     "source_path": str(source), "captured_at": candidate.get("captured_at"),
                     "model_metadata": candidate.get("model_metadata", {}), "input_kind": "saved-asr-input",
                     "repeated_four_word_sequences": candidate.get("repeated_four_word_sequences", 0)}
            entries.append(entry)
            references[sample_id] = {"text": candidate["draft_text"], "status": "draft", "no_speech": False,
                                     "notes": "", "tags": candidate.get("tags", []), "revision": 0,
                                     "updated_at": None}
        identity = hashlib.sha256(canonical([{k: e[k] for k in ("id", "sha256", "source_id")}
                                             for e in entries])).hexdigest()
        write_json(staging / "dataset.json", {"schema_version": 1, "dataset_id": identity,
                                              "created_at": timestamp(), "context": context, "entries": entries})
        write_json(staging / "references.json", references)
        staging.rename(destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def prepare(database, destination, count, minimum_duration=20):
    if count < 1 or minimum_duration < 0:
        raise DatasetError("Count must be positive and minimum duration must not be negative")
    if Path(destination).exists():
        raise DatasetError("Destination already exists; review work will not be overwritten")
    connection = sqlite3.connect(Path(database).resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("BEGIN")
        settings = dict(connection.execute("SELECT key,value FROM app_settings WHERE key LIKE 'audio.%' OR key LIKE 'transcription.%'"))
        dictionary = [dict(row) for row in connection.execute("SELECT canonical,variants FROM dictionary_entries ORDER BY canonical")]
        rows = connection.execute("""
            SELECT v.*, a.url FROM voice_history v JOIN archived_audio_links a
            ON a.owner_id=v.id AND a.owner_kind='voice_history'
            ORDER BY v.created_at DESC, a.created_at DESC
        """).fetchall()
    finally:
        connection.close()
    candidates, seen = [], set()
    for row in rows:
        if row["id"] in seen or not Path(row["url"]).is_file():
            continue
        draft = row["raw_text"]
        if row["text_storage_format"] == "zlib" and row["raw_text_compressed"]:
            draft = zlib.decompress(row["raw_text_compressed"]).decode("utf-8")
        if not draft:
            continue
        seen.add(row["id"])
        info, _ = wav_contents(row["url"])
        if info["duration"] < minimum_duration:
            continue
        words = re.findall(r"\w+", draft.casefold())
        sequences = Counter(tuple(words[i:i + 4]) for i in range(max(0, len(words) - 3)))
        repeated = sum(n - 1 for n in sequences.values() if n > 1)
        candidates.append({"source_path": row["url"], "source_id": row["id"], "draft_text": draft,
                           "captured_at": row["created_at"], "duration": info["duration"],
                           "model_metadata": json.loads(row["model_metadata_json"] or "{}"),
                           "repeated_four_word_sequences": repeated,
                           "tags": ["длинная фраза"] + (["проверить повторы"] if repeated else [])})
    selected = sorted(candidates, key=lambda e: e["duration"], reverse=True)[:count]
    create_dataset(selected, destination, {"source_database": str(Path(database).resolve()),
                                          "settings_at_import": settings, "dictionary_at_import": dictionary,
                                          "historical_configuration_known": False,
                                          "selection": {"minimum_audio_seconds": minimum_duration,
                                                        "maximum_count": count, "order": "duration-descending"},
                                          "provenance": "Saved WAVs normally contain preprocessed ASR input, not raw microphone capture."})
    return len(selected)


class Store:
    def __init__(self, directory):
        self.directory = Path(directory).resolve()
        self.dataset = read_json(self.directory / "dataset.json")
        self.entries = {entry["id"]: entry for entry in self.dataset["entries"]}

    def state(self):
        references = read_json(self.directory / "references.json")
        return {"dataset_id": self.dataset["dataset_id"], "created_at": self.dataset["created_at"],
                "entries": [{**entry, "reference": references[entry["id"]]} for entry in self.entries.values()]}

    def update(self, sample_id, payload):
        if sample_id not in self.entries:
            raise DatasetError("Unknown recording")
        references = read_json(self.directory / "references.json")
        previous = references[sample_id]
        if type(payload.get("revision")) is not int or payload["revision"] != previous["revision"]:
            raise DatasetError("Запись изменена в другой вкладке. Перезагрузи страницу перед сохранением.")
        status, text = payload.get("status"), payload.get("text")
        notes, tags, no_speech = payload.get("notes", ""), payload.get("tags", []), payload.get("no_speech", False)
        if status not in ("draft", "confirmed", "excluded") or not isinstance(text, str):
            raise DatasetError("Invalid reference state or text")
        if not isinstance(notes, str) or not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            raise DatasetError("Invalid notes or tags")
        if type(no_speech) is not bool or len(text) > 100000 or len(notes) > 20000:
            raise DatasetError("Invalid reference fields")
        text = text.strip()
        if status == "confirmed" and ((not text and not no_speech) or (text and no_speech)):
            raise DatasetError("Для пустого эталона отметь «Речи нет». При этой отметке текст должен быть пустым.")
        references[sample_id] = {"text": text, "status": status, "no_speech": no_speech, "notes": notes,
                                 "tags": [tag.strip() for tag in tags if tag.strip()],
                                 "revision": previous["revision"] + 1, "updated_at": timestamp()}
        write_json(self.directory / "references.json", references)
        return references[sample_id]

    def resource(self, relative):
        path = (self.directory / relative).resolve()
        if not path.is_relative_to(self.directory) or not path.is_file():
            raise DatasetError("Recording is missing")
        return path

    def export(self):
        confirmed = [e for e in self.state()["entries"] if e["reference"]["status"] == "confirmed"]
        if not confirmed:
            raise DatasetError("Сначала прослушай и подтверди хотя бы одну запись.")
        entries = []
        for entry in confirmed:
            path = self.resource(entry["audio"])
            if fingerprint(path) != entry["sha256"]:
                raise DatasetError("Audio fingerprint changed: " + entry["id"])
            entries.append({"id": entry["id"], "audio": entry["audio"], "sha256": entry["sha256"],
                            "duration": entry["duration"], "input_kind": entry["input_kind"],
                            "reference": entry["reference"]["text"], "no_speech": entry["reference"]["no_speech"],
                            "tags": entry["reference"]["tags"]})
        snapshot = {"schema_version": 1, "source_dataset_id": self.dataset["dataset_id"],
                    "context": self.dataset["context"], "entries": entries}
        identity = hashlib.sha256(canonical(snapshot)).hexdigest()
        snapshot["snapshot_id"] = identity
        destination = self.directory / "exports" / identity
        if destination.exists():
            if read_json(destination / "dataset.json") != snapshot or any(
                fingerprint(destination / e["audio"]) != e["sha256"] for e in entries
            ):
                raise DatasetError("Existing golden snapshot has changed")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(tempfile.mkdtemp(prefix=".golden-", dir=destination.parent))
            try:
                (staging / "audio").mkdir()
                for entry in entries:
                    shutil.copyfile(self.resource(entry["audio"]), staging / entry["audio"])
                write_json(staging / "dataset.json", snapshot)
                staging.rename(destination)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        return {"snapshot_id": identity, "path": str(destination), "count": len(entries)}


def make_server(store, port):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def reply(self, status, content, content_type="application/json; charset=utf-8", headers=None):
            body = content if isinstance(content, bytes) else json.dumps(content, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            for key, value in (headers or {}).items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
                self.reply(403, {"error": "Local host only"})
                return
            path = urlsplit(self.path).path
            try:
                if path == "/":
                    self.reply(200, Path(__file__).with_name("review.html").read_bytes(), "text/html; charset=utf-8")
                elif path == "/api/dataset":
                    self.reply(200, store.state())
                elif path.startswith("/audio/") and path.endswith(".wav") and path[7:-4] in store.entries:
                    data = store.resource("playback/" + path[7:]).read_bytes()
                    headers = {"Accept-Ranges": "bytes"}
                    requested = self.headers.get("Range")
                    if requested:
                        match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested)
                        if not match or not any(match.groups()):
                            self.reply(416, b"", headers={"Content-Range": f"bytes */{len(data)}"})
                            return
                        first, last = match.groups()
                        start = int(first) if first else max(0, len(data) - int(last))
                        end = min(int(last), len(data) - 1) if first and last else len(data) - 1
                        if start > end or start >= len(data):
                            self.reply(416, b"", headers={"Content-Range": f"bytes */{len(data)}"})
                            return
                        headers["Content-Range"] = f"bytes {start}-{end}/{len(data)}"
                        self.reply(206, data[start:end + 1], "audio/wav", headers)
                    else:
                        self.reply(200, data, "audio/wav", headers)
                else:
                    self.reply(404, {"error": "Not found"})
            except (DatasetError, OSError, ValueError) as error:
                self.reply(400, {"error": str(error)})

        def do_POST(self):
            expected = f"127.0.0.1:{self.server.server_port}"
            if self.headers.get("Host") != expected or self.headers.get("Origin") != "http://" + expected:
                self.reply(403, {"error": "Same-origin local requests only"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 1048576:
                    raise DatasetError("Invalid request size")
                payload = json.loads(self.rfile.read(length))
                path = urlsplit(self.path).path
                if path == "/api/export":
                    self.reply(200, store.export())
                elif path.startswith("/api/references/"):
                    self.reply(200, store.update(path.rsplit("/", 1)[-1], payload))
                else:
                    self.reply(404, {"error": "Not found"})
            except (DatasetError, OSError, ValueError, TypeError, AttributeError) as error:
                self.reply(400, {"error": str(error)})

    return HTTPServer(("127.0.0.1", port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "serve", "export"):
        command = commands.add_parser(name)
        command.add_argument("--data", type=Path, default=DEFAULT_DATA)
        if name == "prepare":
            command.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
            command.add_argument("--count", type=int, default=30)
            command.add_argument("--min-duration", type=float, default=20)
        if name == "serve":
            command.add_argument("--port", type=int, default=8765)
    arguments = parser.parse_args()
    try:
        if arguments.command == "prepare":
            count = prepare(arguments.database, arguments.data, arguments.count, arguments.min_duration)
            print(f"Prepared {count} drafts in {arguments.data}. Confirmed: 0.")
        elif arguments.command == "export":
            print(json.dumps(Store(arguments.data).export(), ensure_ascii=False))
        else:
            server = make_server(Store(arguments.data), arguments.port)
            print(f"Review: http://127.0.0.1:{server.server_port}", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
            finally:
                server.server_close()
    except (DatasetError, OSError, ValueError, sqlite3.Error) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
