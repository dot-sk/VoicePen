"""Score production Swift adapter output using the unchanged frozen native protocols."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Vendor/transcribe-native/tools"))
from evaluate import edit_metrics, normalizers, verify_dataset, verify_policy_digests


def score(dataset_path, adapter_path, native_path):
    pins = json.loads((ROOT / "Vendor/transcribe-native/pins.json").read_text())
    verify_policy_digests(pins)
    entries = verify_dataset(dataset_path, pins["evaluation_inputs"]["dataset_sha256"])
    adapter = json.loads(adapter_path.read_text())
    native = json.loads(native_path.read_text())
    rows = adapter["recordings"]
    if len(rows) != 27 or len({r["sample_id"] for r in rows}) != 27:
        raise ValueError("Incomplete or duplicate adapter corpus")
    if adapter["preprocessing_passes"] != 0:
        raise ValueError("Saved ASR inputs were preprocessed again")
    if adapter["model_sha256"] != native["candidate"]["model_sha256"]:
        raise ValueError("Adapter/native model identity mismatch")
    if adapter["runtime_sha256"] != native["candidate"]["runtime_sha256"]:
        raise ValueError("Adapter/native runtime identity mismatch")
    by_id = {r["sample_id"]: r for r in rows}
    native_by_id = {r["sample_id"]: r for r in native["recordings"]}
    if set(by_id) != {e["id"] for e in entries} or set(by_id) != set(native_by_id):
        raise ValueError("Corpus membership mismatch")
    norms = normalizers()
    failures = []
    results = []
    for entry in entries:
        row = by_id[entry["id"]]
        reference = native_by_id[entry["id"]]
        equal = norms["base"](row["text"]) == norms["base"](reference["raw_text"])
        if not equal:
            failures.append({"sample_id": entry["id"], "check": "raw adapter/native base equality"})
        if row["sample_count"] != round(entry["duration"] * 16000):
            failures.append({"sample_id": entry["id"], "check": "input coverage"})
        if not row["native_backend"].startswith("MTL"):
            failures.append({"sample_id": entry["id"], "check": "required Metal backend"})
        results.append({"sample_id": entry["id"], "native_equal": equal, "protocols": {name: edit_metrics(entry["reference"], row["text"], norm) for name, norm in norms.items()}, "adapter_wall_s": row["adapter_wall_s"], "native_wall_s": statistics.median(c["native_wall_s"] for c in reference["calls"]), "native_compute_s": row["native_compute_s"], "cold_shape_s": row["cold_shape_s"]})
    aggregate = {}
    for protocol in norms:
        aggregate[protocol] = {}
        for unit, rate in [("word", "wer"), ("character", "cer")]:
            counts = {field: sum(r["protocols"][protocol][unit][field] for r in results) for field in ["substitutions", "deletions", "insertions", "edits", "denominator"]}
            aggregate[protocol][unit] = {**counts, rate: counts["edits"] / counts["denominator"] if counts["denominator"] else 0}
    return {"scope": "production Swift adapter raw output, before post-filter and dictionary; not package acceptance", "accepted": not failures, "failures": failures, "model_sha256": adapter["model_sha256"], "package_id": adapter["package_id"], "protocol_hashes": native["protocol_hashes"], "aggregate": aggregate, "recordings": results, "timing": {"cold_load_s": adapter["cold_load_s"], "median_adapter_s": statistics.median(r["adapter_wall_s"] for r in results), "median_first_shape_s": statistics.median(r["cold_shape_s"] for r in results), "median_adapter_overhead_s": statistics.median(r["adapter_wall_s"] - r["native_compute_s"] for r in results), "median_adapter_minus_native_cli_s": statistics.median(r["adapter_wall_s"] - r["native_wall_s"] for r in results), "peak_rss_bytes": adapter["peak_rss_bytes"]}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["dataset", "adapter", "native", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    result = score(args.dataset, args.adapter, args.native)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ["accepted", "failures", "aggregate", "timing"]}, indent=2))
    if not result["accepted"]:
        raise SystemExit(1)
