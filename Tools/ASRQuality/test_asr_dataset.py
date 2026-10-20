import hashlib
from contextlib import closing
import http.client
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import threading
import unittest
import wave

from asr_dataset import DatasetError, Store, create_dataset, make_server, prepare


class DatasetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.audio = self.root / "source.wav"
        with wave.open(str(self.audio), "wb") as output:
            output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            output.writeframes(b"\x00\x00" * 16000)
        self.data = self.root / "corpus"
        self.candidates = [
            {"source_path": str(self.audio), "source_id": str(i), "draft_text": f"Draft {i}", "tags": []}
            for i in range(3)
        ]
        create_dataset(self.candidates, self.data, {})
        self.store = Store(self.data)

    def edit(self, sample_id="sample-001", **changes):
        reference = dict(self.store.state()["entries"][int(sample_id[-3:]) - 1]["reference"])
        reference.update(changes)
        return self.store.update(sample_id, reference)

    def test_preparation_copies_audio_as_drafts_and_refuses_overwrite(self):
        state = self.store.state()
        self.assertEqual([e["reference"]["status"] for e in state["entries"]], ["draft"] * 3)
        entry = state["entries"][0]
        self.assertEqual((self.data / entry["audio"]).read_bytes(), self.audio.read_bytes())
        self.assertEqual(entry["sha256"], hashlib.sha256(self.audio.read_bytes()).hexdigest())
        self.edit(text="My correction")
        with self.assertRaises(DatasetError):
            create_dataset(self.candidates, self.data, {})
        self.assertEqual(Store(self.data).state()["entries"][0]["reference"]["text"], "My correction")

    def history_database(self):
        database = self.root / "history.sqlite"
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.executescript("""
                CREATE TABLE voice_history (id TEXT, created_at REAL, duration REAL,
                  raw_text TEXT, raw_text_compressed BLOB, text_storage_format TEXT,
                  model_metadata_json TEXT);
                CREATE TABLE archived_audio_links (owner_id TEXT, owner_kind TEXT, url TEXT, created_at REAL);
                CREATE TABLE app_settings (key TEXT, value TEXT);
                CREATE TABLE dictionary_entries (canonical TEXT, variants TEXT);
            """)
            connection.execute("INSERT INTO voice_history VALUES ('one',1,1,'Hello',NULL,'plain','{}')")
            connection.execute("INSERT INTO archived_audio_links VALUES ('one','voice_history',?,1)", (str(self.audio),))
            connection.execute("INSERT INTO archived_audio_links VALUES ('one','voice_history','/missing.wav',2)")
        return database

    def test_history_is_read_only_and_missing_audio_is_skipped(self):
        database = self.history_database()
        before = database.read_bytes()
        destination = self.root / "imported"
        prepare(database, destination, 30, minimum_duration=0)
        self.assertEqual(database.read_bytes(), before)
        imported = Store(destination).state()
        self.assertEqual(len(imported["entries"]), 1)
        self.assertEqual(imported["entries"][0]["reference"]["text"], "Hello")

    def test_actual_audio_duration_filters_and_orders_without_short_backfill(self):
        database = self.history_database()
        for identifier, seconds in (("two", 25), ("three", 40)):
            long_audio = self.root / (identifier + ".wav")
            with wave.open(str(long_audio), "wb") as output:
                output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                output.writeframes(b"\x00\x00" * 16000 * seconds)
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("INSERT INTO voice_history VALUES (?,2,1,'Long',NULL,'plain','{}')", (identifier,))
                connection.execute("INSERT INTO archived_audio_links VALUES (?,'voice_history',?,2)", (identifier, str(long_audio)))
        prepare(database, self.root / "long-only", 30, minimum_duration=20)
        selected = Store(self.root / "long-only").state()["entries"]
        self.assertEqual([entry["duration"] for entry in selected], [40, 25])

    def test_corpus_with_no_qualifying_audio_does_not_create_review_work(self):
        database = self.history_database()
        with self.assertRaises(DatasetError):
            prepare(database, self.root / "too-short", 30, minimum_duration=20)
        self.assertFalse((self.root / "too-short").exists())

    def test_tooling_changes_trigger_the_existing_code_check_path(self):
        script = Path(__file__).resolve().parents[2] / "scripts/code-impacting-changes.sh"
        result = subprocess.run(["bash", str(script)], input="Tools/ASRQuality/asr_dataset.py\n", text=True)
        self.assertEqual(result.returncode, 0)

    def test_corrections_and_confirmation_persist(self):
        self.edit(text="Настроить PostgreSQL", status="confirmed", notes="Checked by listening", tags=["terms"])
        actual = Store(self.data).state()["entries"][0]["reference"]
        self.assertEqual((actual["text"], actual["status"], actual["notes"]),
                         ("Настроить PostgreSQL", "confirmed", "Checked by listening"))

    def test_empty_gold_requires_explicit_no_speech(self):
        with self.assertRaises(DatasetError):
            self.edit(text="", status="confirmed")
        self.assertEqual(self.store.state()["entries"][0]["reference"]["revision"], 0)
        self.edit(text="", status="confirmed", no_speech=True)
        exported = json.loads(Path(self.store.export()["path"]).joinpath("dataset.json").read_text())
        self.assertEqual(exported["entries"][0]["reference"], "")
        self.assertTrue(exported["entries"][0]["no_speech"])

    def test_stale_save_cannot_replace_newer_edit(self):
        stale = dict(self.store.state()["entries"][0]["reference"])
        self.edit(text="New correction")
        stale["text"] = "Old tab"
        with self.assertRaises(DatasetError):
            self.store.update("sample-001", stale)
        self.assertEqual(self.store.state()["entries"][0]["reference"]["text"], "New correction")

    def test_exports_only_confirmed_entries_and_keeps_old_snapshots(self):
        self.edit(text="Первый эталон", status="confirmed")
        self.edit("sample-002", status="excluded")
        first = self.store.export()
        original = Path(first["path"]).joinpath("dataset.json").read_bytes()
        self.assertEqual(first["count"], 1)
        self.assertEqual(self.store.export(), first)
        self.edit(text="Исправленный эталон", status="confirmed")
        second = self.store.export()
        self.assertNotEqual(first["snapshot_id"], second["snapshot_id"])
        self.assertEqual(Path(first["path"]).joinpath("dataset.json").read_bytes(), original)

    def test_export_rejects_empty_or_changed_audio(self):
        with self.assertRaises(DatasetError):
            self.store.export()
        self.edit(status="confirmed")
        entry = self.store.state()["entries"][0]
        (self.data / entry["audio"]).write_bytes(b"changed")
        with self.assertRaises(DatasetError):
            self.store.export()
        self.assertFalse((self.data / "exports").exists())

    def test_http_supports_audio_seeking_and_rejects_unrelated_access(self):
        server = make_server(self.store, 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 2)
        self.addCleanup(server.shutdown)
        connection = http.client.HTTPConnection(*server.server_address, timeout=3)
        self.addCleanup(connection.close)
        connection.request("GET", "/audio/sample-001.wav", headers={"Range": "bytes=4-11"})
        response = connection.getresponse()
        self.assertEqual(response.status, 206)
        playback = (self.data / "playback/sample-001.wav").read_bytes()
        self.assertEqual(response.read(), playback[4:12])
        connection.request("GET", "/audio/../../source.wav")
        response = connection.getresponse()
        self.assertEqual(response.status, 404)
        response.read()
        connection.request("POST", "/api/references/sample-001", body=b"{}",
                           headers={"Origin": "https://unrelated.example", "Content-Type": "application/json"})
        response = connection.getresponse()
        self.assertEqual(response.status, 403)
        response.read()
        self.assertEqual(self.store.state()["entries"][0]["reference"]["revision"], 0)


if __name__ == "__main__":
    unittest.main()
