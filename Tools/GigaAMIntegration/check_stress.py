"""Validate recorded native window coverage for the two-hour adapter fixture."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--log", type=Path, required=True)
parser.add_argument("--result", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
result = json.loads(args.result.read_text())
if result["status"] != "completed" or result["input_samples"] != 115_200_000 or result["anchor_occurrences"] < 2:
    raise ValueError("Incomplete two-hour adapter result")
pattern = r"stock25 window=(\d+) retained=(\d+):(\d+) encoded=(\d+):(\d+) mel=(\d+):(\d+)"
windows = [tuple(map(int, row)) for row in re.findall(pattern, args.log.read_text())]
if not windows:
    raise ValueError("Missing native window evidence")
cursor = 0
for index, (number, start, end, encoded_start, encoded_end, mel_start, mel_end) in enumerate(windows):
    if number != index or start != cursor or not encoded_start <= start < end <= encoded_end:
        raise ValueError(f"Gap, duplication or invalid retention at window {index}")
    if encoded_end - encoded_start > 625 or mel_end - mel_start > 2500:
        raise ValueError(f"Changed 25-second bound at window {index}")
    cursor = end
if cursor != 180_000:
    raise ValueError(f"Incomplete stitched frame coverage: {cursor}")
evidence = {
    "input_samples": result["input_samples"], "retained_frames": cursor,
    "window_count": len(windows), "contiguous_retention": True,
    "bounded_25_seconds": True, "anchor_occurrences": result["anchor_occurrences"],
    "wall_s": result["wall_s"], "peak_rss_bytes": result["peak_rss_bytes"],
    "model_sha256": result["model_sha256"], "package_id": result["package_id"],
}
args.output.write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence))
