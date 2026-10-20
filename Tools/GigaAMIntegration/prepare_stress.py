"""Prepare a bounded 120-minute private Meeting fixture with speech at both ends."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import soundfile as sf

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--speech", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
speech, rate = sf.read(args.speech, dtype="float32")
if rate != 16000 or speech.ndim != 1 or not np.isfinite(speech).all():
    raise ValueError("Expected saved 16k mono finite ASR input")
total = 120 * 60 * rate
if len(speech) * 2 >= total:
    raise ValueError("Speech fixture too long")
args.output.parent.mkdir(parents=True, exist_ok=True)
if args.output.exists():
    raise FileExistsError(args.output)
silence = np.zeros(60 * rate, dtype="float32")
with sf.SoundFile(args.output, mode="w", samplerate=rate, channels=1, subtype="FLOAT", format="WAV") as output:
    output.write(speech)
    remaining = total - 2 * len(speech)
    while remaining:
        count = min(remaining, len(silence))
        output.write(silence[:count])
        remaining -= count
    output.write(speech)
metadata = {"duration_s": 7200, "sample_count": total, "sample_rate": rate, "speech_spans": [[0, len(speech) / rate], [(total - len(speech)) / rate, 7200]], "source_sha256": hashlib.file_digest(args.speech.open("rb"), "sha256").hexdigest(), "fixture_sha256": hashlib.file_digest(args.output.open("rb"), "sha256").hexdigest()}
args.output.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(metadata))
