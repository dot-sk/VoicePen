"""Score production Whisper output using the existing frozen research protocols."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import statistics
import unicodedata

import jiwer


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--evaluation", type=Path, required=True)
    parser.add_argument("--normalizers", type=Path, required=True)
    parser.add_argument("--hesitations", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    dataset = json.loads(args.dataset.read_text())
    evaluation = json.loads(args.evaluation.read_text())
    assert dataset["snapshot_id"] == evaluation["snapshot_id"]
    entries = {entry["id"]: entry for entry in dataset["entries"]}
    rows = evaluation["recordings"]
    assert len(entries) == 27 and len(rows) == 81
    assert {(row["sample_id"], row["repeat"]) for row in rows} == {
        (sample_id, repeat) for sample_id in entries for repeat in range(3)
    }
    assert all(row["status"] == 0 for row in rows)
    assert all(row["sample_count"] == round(entries[row["sample_id"]]["duration"] * 16_000) for row in rows)
    namespace = {"re": re, "unicodedata": unicodedata}
    for node in ast.parse(args.normalizers.read_text()).body:
        if isinstance(node, ast.FunctionDef) and node.name in {"base", "normalize"}:
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(args.normalizers), "exec"), namespace)
    base = namespace["base"]
    aliases = {}
    for canonical, variants in json.loads(args.policy.read_text())["aliases"].items():
        for variant in [canonical, *variants]:
            key, value = tuple(base(variant)), tuple(base(canonical))
            assert key not in aliases or aliases[key] == value
            aliases[key] = value
    namespace.update(aliases=aliases, max_length=max(map(len, aliases)))
    for node in ast.parse(args.hesitations.read_text()).body:
        needed_assignment = isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id in {"dash", "tokens", "hesitation"} for target in node.targets
        )
        if needed_assignment or isinstance(node, ast.FunctionDef) and node.name == "strip_hesitations":
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(args.hesitations), "exec"), namespace)
    normalize = namespace["normalize"]
    strip = namespace["strip_hesitations"]

    def score(records, normalizer, filter_hesitations=False):
        refs, hyps = [], []
        for row in records:
            reference, hypothesis = entries[row["sample_id"]]["reference"], row["text"]
            if filter_hesitations:
                reference, hypothesis = strip(reference)[0], strip(hypothesis)[0]
            refs.append(normalizer(reference))
            hyps.append(normalizer(hypothesis))
        word = jiwer.process_words(refs, hyps)
        return {"wer": word.wer, "cer": jiwer.cer(refs, hyps),
                "reference_words": word.hits + word.substitutions + word.deletions,
                "word_edits": word.substitutions + word.deletions + word.insertions}

    baseline = [json.loads(line) for line in args.baseline.read_text().splitlines() if line]
    assert len(baseline) == 81
    assert {(row["sample_id"], row["repeat"]) for row in baseline} == {(row["sample_id"], row["repeat"]) for row in rows}
    summaries = {}
    for name, records in [("production-metal", rows), ("historical-metal", baseline)]:
        summaries[name] = {
            "base": score(records, lambda text: " ".join(base(text))),
            "aliases": score(records, normalize),
            "hesitation_filtered_base": score(records, lambda text: " ".join(base(text)), True),
            "hesitation_filtered_aliases": score(records, normalize, True),
            "median_inference_s": statistics.median(row["native_wall_s"] for row in records),
        }
    previous = {(row["sample_id"], row["repeat"]): row for row in baseline}
    result = {"snapshot_id": dataset["snapshot_id"], "recordings": 27, "calls": len(rows),
              "source_hashes": {name: digest(getattr(args, name)) for name in ["dataset", "evaluation", "normalizers", "hesitations", "policy", "baseline"]},
              "summaries": summaries,
              "exact_baseline_matches": sum(row["text"] == previous[row["sample_id"], row["repeat"]]["text"] for row in rows),
              "trimmed_baseline_matches": sum(row["text"].strip() == previous[row["sample_id"], row["repeat"]]["text"].strip() for row in rows),
              "model_load_s": evaluation["model_load_s"], "warmup_s": evaluation["warmup_s"],
              "median_adapter_wall_s": statistics.median(row["adapter_wall_s"] for row in rows),
              "timing_scope": "Native inference excludes audio reading, model loading and warmup. Adapter wall includes audio reading. Sequential host measurements.",
              "q5_quality": "unmeasured"}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["summaries"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
