import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import unicodedata

import jiwer

ROOT = Path(__file__).resolve().parent
report_path = ROOT / 'report.json'
report = json.loads(report_path.read_text())
previous = ROOT.parent / 'gigaam-20261019'
policy_path = previous / 'term-spelling-policy.json'
policy = json.loads(policy_path.read_text())
namespace = {'re': re, 'unicodedata': unicodedata}
for node in ast.parse((previous / 'rescore_spellings.py').read_text()).body:
    if isinstance(node, ast.FunctionDef) and node.name in {'base', 'normalize'}:
        exec(compile(ast.Module(body=[node], type_ignores=[]), 'frozen-normalizer', 'exec'), namespace)
base, normalize = namespace['base'], namespace['normalize']
aliases = {}
for canonical, variants in policy['aliases'].items():
    for variant in [canonical, *variants]:
        key, value = tuple(base(variant)), tuple(base(canonical))
        assert key not in aliases or aliases[key] == value
        aliases[key] = value
namespace.update(aliases=aliases, max_length=max(map(len, aliases)))

dash = r'[-‐‑–—]'
tokens = re.compile(r'[^\W\d_]+(?:' + dash + r'[^\W\d_]+)*', re.UNICODE)
hesitation = re.compile(r'(?:э+|а{2,}|м{3,}|хм+|[аэым]+(?:' + dash + r'[аэым]+)+)', re.IGNORECASE)

def strip_hesitations(text):
    removed = []
    def replace(match):
        token = match.group()
        if hesitation.fullmatch(token):
            removed.append({'text': token, 'start': match.start(), 'end': match.end()})
            return ' '
        return token
    return tokens.sub(replace, text), removed

assert strip_hesitations('Э-э, а-а-а, э-ээ, э-э-а, а-м-м, хмм, ммм, Аа, эээ.')[0].strip(' ,.') == ''
for text in ['А потом мы выбрали 35 мм, а не 50 мм.', 'эм эл, эм эр, эмэлем, ML и email',
             'Ну вот, или или, вы вы вы, и-и-и', 'проверь, проверю, эхо, хмель, мама']:
    assert strip_hesitations(text) == (text, [])
assert normalize('Jira GPT ML') == normalize('жира джипити эмэлем')
assert normalize('ML') != normalize('email')

def metrics(refs, hyps, normalizer):
    refs = [normalizer(text) for text in refs]
    hyps = [normalizer(text) for text in hyps]
    word = jiwer.process_words(refs, hyps)
    return {'wer': word.wer, 'cer': jiwer.cer(refs, hyps),
            'substitutions': word.substitutions, 'deletions': word.deletions, 'insertions': word.insertions,
            'word_edits': word.substitutions + word.deletions + word.insertions,
            'reference_words': word.hits + word.substitutions + word.deletions}

summaries = {}
audit = []
models = list(report['summaries'])
for model in models:
    refs, hyps, clean_refs, clean_hyps = [], [], [], []
    removed_ref, removed_hyp = Counter(), Counter()
    for sample in report['paired_recordings']:
        reference, reference_spans = strip_hesitations(sample['reference'])
        assert len(sample['models'][model]) == 3
        for run in sample['models'][model]:
            assert run['status'] == 0
            hypothesis, hypothesis_spans = strip_hesitations(run['text'])
            refs.append(sample['reference']); hyps.append(run['text'])
            clean_refs.append(reference); clean_hyps.append(hypothesis)
            removed_ref.update(span['text'].casefold() for span in reference_spans)
            removed_hyp.update(span['text'].casefold() for span in hypothesis_spans)
            audit.append({'model': model, 'sample_id': sample['id'], 'repeat': run['repeat'],
                          'reference_removed': reference_spans, 'hypothesis_removed': hypothesis_spans,
                          'filtered_reference': reference, 'filtered_hypothesis': hypothesis})
    assert len(refs) == 81
    before = {label: metrics(refs, hyps, fn) for label, fn in [('raw', lambda text: ' '.join(base(text))), ('term_normalized', normalize)]}
    after = {label: metrics(clean_refs, clean_hyps, fn) for label, fn in [('raw', lambda text: ' '.join(base(text))), ('term_normalized', normalize)]}
    for label in before:
        for key in ['wer', 'cer', 'word_edits', 'reference_words']:
            assert abs(before[label][key] - report['summaries'][model][label][key]) < 1e-12
    summaries[model] = {'recordings': 27, 'calls': 81, 'before': before, 'after': after,
                        'removed_reference_spans_per_repeat': sum(removed_ref.values()) / 3,
                        'removed_hypothesis_spans_per_repeat': sum(removed_hyp.values()) / 3,
                        'removed_hypothesis_forms_all_repeats': dict(removed_hyp)}

result = {'created_at': datetime.now(timezone.utc).isoformat(), 'snapshot_id': report['snapshot_id'],
          'source_report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
          'term_spelling_policy_sha256': hashlib.sha256(policy_path.read_bytes()).hexdigest(),
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'policy': {'scope': 'Post-hoc diagnostic requested by user; identical reference-independent filter applied to references and every model hypothesis before the original normalization. No new inference, no reference edits.',
                     'token_regex': tokens.pattern, 'hesitation_fullmatch_regex': hesitation.pattern,
                     'removed': ['э and elongated э', 'аа and longer а', 'ммм and longer м', 'хм and longer хмм', 'hyphenated sounds built only from а/э/ы/м, including а-а, э-э-а, а-м-м'],
                     'preserved': ['single а', 'ну, вот, типа and all ordinary words', 'lexical repetitions and stutters including и-и-и', 'эм эл, эм эр and other letter names', 'мм, including 35 мм', 'unknown or ambiguous sounds outside the explicit rules'],
                     'caveat': 'Hesitations are identified from spelling, not independently relistened audio. This removes only nonlexical sound spellings; it is not a semantic error metric. CER includes spaces.'},
          'summaries': summaries, 'audit': audit}
(ROOT / 'hesitation-normalized.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
lines = ['# WER/CER без звуков колебания', '',
         'Те же 27 записей, 3 повтора. Одинаковый фильтр применён к эталонам и результатам всех моделей до прежней нормализации. Нового распознавания не было.', '',
         '| Модель / движок | WER без колебаний | CER без колебаний | WER также с допусками терминов | CER также с допусками терминов |',
         '|---|---:|---:|---:|---:|']
for model, row in summaries.items():
    value = row['after']
    lines.append(f"| {model} | {value['raw']['wer']:.2%} | {value['raw']['cer']:.2%} | {value['term_normalized']['wer']:.2%} | {value['term_normalized']['cer']:.2%} |")
lines += ['', 'Убраны э/эээ, аа/ааа, ммм, хм/хмм и дефисные сочетания звуков а/э/ы/м. Сохранены одиночное а, ну/вот/типа, словесные повторы, названия букв и мм как единица измерения.', '',
          'Фильтр определяется написанием, без повторного прослушивания аудио. Он задан после основного бенчмарка по запросу пользователя. Исходные метрики сохранены.', '',
          'Полный аудит удалённых фрагментов и метрики до/после: `hesitation-normalized.json`.', '']
(ROOT / 'hesitation-normalized.md').write_text('\n'.join(lines))
print(json.dumps(summaries, ensure_ascii=False, indent=2))
