from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys
import unicodedata

import jiwer
import numpy as np

ROOT = Path(__file__).resolve().parent
original = json.loads((ROOT / 'report.json').read_text())
policy_path = ROOT / 'term-spelling-policy.json'
policy = json.loads(policy_path.read_text())

def base(text):
    ones = 'ноль один два три четыре пять шесть семь восемь девять десять одиннадцать двенадцать тринадцать четырнадцать пятнадцать шестнадцать семнадцать восемнадцать девятнадцать'.split()
    tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто']
    result = []
    for token in re.findall(r'[^\W_]+', unicodedata.normalize('NFKC', text).casefold().replace('ё', 'е'), re.UNICODE):
        if token.isascii() and token.isdigit() and int(token) <= 99:
            n = int(token)
            result.extend(ones[n].split() if n < 20 else (tens[n // 10] + (' ' + ones[n % 10] if n % 10 else '')).split())
        else:
            result.append(token)
    return result

aliases = {}
for canonical, variants in policy['aliases'].items():
    for variant in [canonical, *variants]:
        key, value = tuple(base(variant)), tuple(base(canonical))
        assert key not in aliases or aliases[key] == value, variant
        aliases[key] = value
max_length = max(map(len, aliases))

def normalize(text):
    tokens = base(text)
    output = []
    index = 0
    while index < len(tokens):
        for size in range(min(max_length, len(tokens) - index), 0, -1):
            key = tuple(tokens[index:index+size])
            if key in aliases:
                output.extend(aliases[key])
                index += size
                break
        else:
            output.append(tokens[index])
            index += 1
    return ' '.join(output)

assert normalize('Jira GPT ML') == normalize('жира джипити эмэлем')
for left, right in [('ML', 'email'), ('ML', 'эмэйл'), ('проверь', 'проверю'), ('выбирай', 'выбирает'), ('дополни', 'дополню')]:
    assert normalize(left) != normalize(right), (left, right)

entries = {row['id']: row for row in original['paired_recordings']}
models = ['whisper-current', 'gigaam-int8-whole']
all_runs = {name: [run for row in entries.values() for run in row[name]['outputs']] for name in models}
if '--include-rnnt' in sys.argv:
    rnnt_root = ROOT.parent / 'gigaam-v3-rnnt-20261019'
    rnnt = [json.loads(line) for line in (rnnt_root / 'runs.jsonl').read_text().splitlines() if line.strip()]
    assert len(rnnt) == 81
    assert json.loads((rnnt_root / 'run-process.json').read_text())['exit_code'] == 0
    models.append('gigaam-v3-rnnt-swift')
    all_runs[models[-1]] = rnnt

summaries = {}
paired = []
for name, runs in all_runs.items():
    assert {(row['sample_id'], row['repeat']) for row in runs} == {(sid, repeat) for sid in entries for repeat in range(3)}
    assert all(row['status'] == 0 and row['sample_count'] == round(entries[row['sample_id']]['duration_s'] * 16000) for row in runs)
    refs = [normalize(entries[row['sample_id']]['reference']) for row in runs]
    hyps = [normalize(row['text']) for row in runs]
    words = jiwer.process_words(refs, hyps)
    raw_refs = [' '.join(base(entries[row['sample_id']]['reference'])) for row in runs]
    raw_hyps = [' '.join(base(row['text'])) for row in runs]
    raw_words = jiwer.process_words(raw_refs, raw_hyps)
    summaries[name] = {'recordings': 27, 'calls': len(runs), 'raw_wer': raw_words.wer, 'raw_cer': jiwer.cer(raw_refs, raw_hyps), 'raw_word_edits_per_repeat': (raw_words.substitutions + raw_words.deletions + raw_words.insertions) / 3, 'raw_substitutions_per_repeat': raw_words.substitutions / 3, 'raw_deletions_per_repeat': raw_words.deletions / 3, 'raw_insertions_per_repeat': raw_words.insertions / 3, 'term_normalized_wer': words.wer, 'term_normalized_cer': jiwer.cer(refs, hyps), 'word_edits_per_repeat': (words.substitutions + words.deletions + words.insertions) / 3, 'reference_words_per_repeat': (words.hits + words.substitutions + words.deletions) / 3, 'substitutions_per_repeat': words.substitutions / 3, 'deletions_per_repeat': words.deletions / 3, 'insertions_per_repeat': words.insertions / 3, 'median_native_s': statistics.median(row['native_wall_s'] for row in runs), 'corpus_sum_recording_medians_s': sum(statistics.median(row['native_wall_s'] for row in runs if row['sample_id'] == sid) for sid in entries)}
    clear_runs = [row for row in runs if 'неразборчиво' not in entries[row['sample_id']]['reference'].casefold()]
    clear_refs = [entries[row['sample_id']]['reference'] for row in clear_runs]
    clear_hyps = [row['text'] for row in clear_runs]
    summaries[name]['without_unclear_references'] = {
        'recordings': len({row['sample_id'] for row in clear_runs}),
        'raw_wer': jiwer.wer([' '.join(base(text)) for text in clear_refs], [' '.join(base(text)) for text in clear_hyps]),
        'raw_cer': jiwer.cer([' '.join(base(text)) for text in clear_refs], [' '.join(base(text)) for text in clear_hyps]),
        'term_normalized_wer': jiwer.wer([normalize(text) for text in clear_refs], [normalize(text) for text in clear_hyps]),
        'term_normalized_cer': jiwer.cer([normalize(text) for text in clear_refs], [normalize(text) for text in clear_hyps]),
    }
    summaries[name]['stable_recordings'] = sum(len({row['text'] for row in runs if row['sample_id'] == sid}) == 1 for sid in entries)
    for row in runs:
        ref = normalize(entries[row['sample_id']]['reference'])
        hyp = normalize(row['text'])
        word = jiwer.process_words(ref, hyp)
        row['term_word_edits'] = word.substitutions + word.deletions + word.insertions
        row['term_errors'] = [{'reference': ' '.join(word.references[0][c.ref_start_idx:c.ref_end_idx]), 'hypothesis': ' '.join(word.hypotheses[0][c.hyp_start_idx:c.hyp_end_idx])} for c in word.alignments[0] if c.type != 'equal']
for sid, entry in entries.items():
    row = {'id': sid, 'reference': entry['reference']}
    for name in models:
        selected = [run for run in all_runs[name] if run['sample_id'] == sid]
        row[name] = {'median_term_word_edits': statistics.median(run['term_word_edits'] for run in selected), 'first_output': selected[0]['text'], 'term_errors': selected[0]['term_errors'], 'unique_outputs': len({run['text'] for run in selected})}
    paired.append(row)
comparisons = {}
for name in models[1:]:
    deltas = np.array([row[name]['median_term_word_edits'] - row['whisper-current']['median_term_word_edits'] for row in paired])
    counts = np.array([len(normalize(row['reference']).split()) for row in paired])
    indices = np.random.default_rng(20261019).integers(0, 27, size=(10000, 27))
    bootstrap = deltas[indices].sum(axis=1) / counts[indices].sum(axis=1)
    comparisons[name] = {'better': int((deltas < 0).sum()), 'worse': int((deltas > 0).sum()), 'equal': int((deltas == 0).sum()), 'wer_delta_vs_whisper': float(deltas.sum() / counts.sum()), 'paired_bootstrap_ci95': np.quantile(bootstrap, [.025, .975]).tolist()}
result = {'created_at': datetime.now(timezone.utc).isoformat(), 'snapshot_id': original['snapshot_id'], 'policy_sha256': hashlib.sha256(policy_path.read_bytes()).hexdigest(), 'policy': policy, 'scope': 'Secondary spelling-normalized diagnostic; original WER/CER remain unchanged. Same model-independent policy for references and all hypotheses; 27 independent recordings. Not a semantic-accuracy metric.', 'summaries': summaries, 'comparisons': comparisons, 'paired_recordings': paired}
output_name = 'spelling-normalized-with-rnnt.json' if '--include-rnnt' in sys.argv else 'spelling-normalized.json'
(ROOT / output_name).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'summaries': summaries, 'comparisons': comparisons}, ensure_ascii=False, indent=2))
