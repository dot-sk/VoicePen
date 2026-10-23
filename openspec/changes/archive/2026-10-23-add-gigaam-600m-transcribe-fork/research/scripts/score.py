import ast,hashlib,json,re,statistics,unicodedata
from pathlib import Path
import jiwer,numpy as np
r=Path(__file__).resolve().parent;prev=r.parent/'gigaam-20261019';cpp=r.parent/'transcribe-cpp-20261019'
corpus=json.loads((prev/'corpus.json').read_text());snapshot_path=r.parents[1]/'exports'/corpus['snapshot_id']/'dataset.json';entries={e['id']:e for e in json.loads(snapshot_path.read_text())['entries']};assert len(entries)==27
ns={'re':re,'unicodedata':unicodedata}
for file,functions in [(prev/'rescore_spellings.py',{'base','normalize'}),(cpp/'rescore_hesitations.py',{'strip_hesitations'})]:
 for node in ast.parse(file.read_text()).body:
  if isinstance(node,ast.FunctionDef) and node.name in functions:exec(compile(ast.Module(body=[node],type_ignores=[]),'frozen-normalizer','exec'),ns)
base,normalize=ns['base'],ns['normalize'];policy_path=prev/'term-spelling-policy.json';policy=json.loads(policy_path.read_text());aliases={}
for canonical,variants in policy['aliases'].items():
 for variant in [canonical,*variants]:
  key,value=tuple(base(variant)),tuple(base(canonical));assert key not in aliases or aliases[key]==value;aliases[key]=value
# Compile the exact frozen regex assignment expressions, with no report-writing execution.
for node in ast.parse((cpp/'rescore_hesitations.py').read_text()).body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id in {'dash','tokens','hesitation'} for t in node.targets):exec(compile(ast.Module(body=[node],type_ignores=[]),'frozen-hesitation-regex','exec'),ns)
ns.update(aliases=aliases,max_length=max(map(len,aliases)));strip=ns['strip_hesitations'];raw=lambda t:' '.join(base(t))
assert normalize('Jira GPT ML')==normalize('жира джипити эмэлем');assert strip('35 мм, эм эл, а, ну вот')[1]==[]
def metrics(rows,normalizer,hes=False):
 refs=[entries[x['sample_id']]['reference'] for x in rows];hyps=[x['text'] for x in rows]
 if hes:refs=[strip(t)[0] for t in refs];hyps=[strip(t)[0] for t in hyps]
 refs=list(map(normalizer,refs));hyps=list(map(normalizer,hyps));w=jiwer.process_words(refs,hyps)
 return {'wer':w.wer,'cer':jiwer.cer(refs,hyps),'substitutions':w.substitutions,'deletions':w.deletions,'insertions':w.insertions,'word_edits':w.substitutions+w.deletions+w.insertions,'reference_words':w.hits+w.substitutions+w.deletions}
def summary(rows):
 ids={x['sample_id'] for x in rows}
 return {'recordings':len(ids),'calls':len(rows),'original':{label:metrics(rows,norm) for label,norm in [('raw',raw),('aliases',normalize)]},'hesitations_removed':{label:metrics(rows,norm,True) for label,norm in [('raw',raw),('aliases',normalize)]},'median_native_s':statistics.median(x['native_wall_s'] for x in rows),'p95_native_s':float(np.quantile([x['native_wall_s'] for x in rows],.95)),'corpus_sum_recording_medians_s':sum(statistics.median(x['native_wall_s'] for x in rows if x['sample_id']==sid) for sid in ids),'stable_recordings':sum(len({x['text'] for x in rows if x['sample_id']==sid})==1 for sid in ids),'native_components_median_ms':{k:statistics.median(x[k] for x in rows) for k in ['mel_ms','encode_ms','decode_ms'] if k in rows[0]}}
all_runs={};metadata={}
for name in ['f16-whole','f16-stock25','q8-whole','q8-stock25','mlx-f16-whole']:
 p=r/name/'runs.jsonl'
 if not p.exists():continue
 rows=[json.loads(t) for t in p.read_text().splitlines()];assert len(rows)==81,(name,len(rows));assert {(x['sample_id'],x['repeat']) for x in rows}=={(sid,i) for sid in entries for i in range(3)}
 assert all(x['status']==0 and x['sample_count']==round(entries[x['sample_id']]['duration']*16000) for x in rows)
 if name=='mlx-f16-whole':assert json.loads((r/'reference-process.json').read_text())['exit_code']==0
 else:assert json.loads((r/name/'process.json').read_text())['exit_code']==0
 all_runs[name]=rows;metadata[name]=json.loads((r/name/'metadata.json').read_text())
ab_folder=r/'head-ab-f16-whole'
if (ab_folder/'process.json').exists():
 assert json.loads((ab_folder/'process.json').read_text())['exit_code']==0
 ab_rows=[json.loads(t) for t in (ab_folder/'runs.jsonl').read_text().splitlines()];assert len(ab_rows)==162
 for config in ['cpu-head','gpu-head']:
  name='head-ab-'+config;all_runs[name]=[x for x in ab_rows if x['config']==config];assert len(all_runs[name])==81
  metadata[name]=json.loads((ab_folder/'metadata.json').read_text())
for name,path in [('historical-mlx-int8-whole',prev/'gigaam-int8-whole/asr/runs.jsonl'),('historical-v3-ctc-q8',cpp/'gigaam-v3-e2e-ctc/runs.jsonl'),('historical-transcribe-whisper-turbo-q8',cpp/'whisper-turbo-q8/runs.jsonl'),('historical-whisper-cpp-turbo-q8',prev/'whisper-current/asr/runs.jsonl')]:all_runs[name]=[json.loads(t) for t in path.read_text().splitlines()]
summaries={}
for name,rows in all_runs.items():
 summaries[name]=summary(rows);summaries[name]['strata']={label:summary([x for x in rows if predicate(entries[x['sample_id']])]) for label,predicate in [('at_most_25s',lambda e:e['duration']<=25),('over_25s',lambda e:e['duration']>25),('clear_references',lambda e:'неразборчиво' not in e['reference'].casefold())]}
assert abs(summaries['historical-mlx-int8-whole']['original']['raw']['wer']-.088315)<1e-6
paired=[{'id':sid,'duration_s':e['duration'],'reference':e['reference'],'models':{n:[x for x in rows if x['sample_id']==sid] for n,rows in all_runs.items()}} for sid,e in entries.items()]
parity=json.loads((r/'parity.json').read_text())
report={'snapshot_id':corpus['snapshot_id'],'corpus_audio_seconds':sum(e['duration'] for e in entries.values()),'parity':parity,'metadata':metadata,'summaries':summaries,'paired_recordings':paired,'scoring':{'normalizer_sha256':hashlib.sha256((prev/'rescore_spellings.py').read_bytes()).hexdigest(),'hesitations_sha256':hashlib.sha256((cpp/'rescore_hesitations.py').read_bytes()).hexdigest(),'aliases_sha256':hashlib.sha256(policy_path.read_bytes()).hexdigest(),'snapshot_sha256':hashlib.sha256(snapshot_path.read_bytes()).hexdigest(),'cer_includes_spaces':True,'reference_policy':'immutable accepted ChatGPT refs, including two unclear markers'}}
(r/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
lines=['# GigaAM Multilingual 600M через transcribe.cpp Metal','','27 файлов, 969.232 секунды. На файл 3 последовательных вызова, 4 CPU threads, timestamps none, без prompt/vocabulary. Модель и warmup исключены из inference timing. Входы оригинальные float32 WAV 16 kHz mono, hashes/sample counts проверены.','','| Конфигурация | WER | CER | WER aliases | CER aliases | WER без hesitation + aliases | CER без hesitation + aliases | median s | sum medians s |','|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for name,s in summaries.items():
 a=s['original']['raw'];b=s['original']['aliases'];c=s['hesitations_removed']['aliases'];lines.append(f"| {name} | {a['wer']:.4%} | {a['cer']:.4%} | {b['wer']:.4%} | {b['cer']:.4%} | {c['wer']:.4%} | {c['cer']:.4%} | {s['median_native_s']:.5f} | {s['corpus_sum_recording_medians_s']:.5f} |")
lines+=['','Полные четыре варианта scoring, raw/aliases до и после hesitation filter, и страты ≤25s/>25s/clear refs лежат в report.json. CER включает пробелы. Hesitation filter одинаков для references и hypotheses, взят без изменений из frozen scorer. Нормализация не меняет эталоны.','','## Перенос и parity','','Исходник transcribe.cpp закреплён на `1dc22facfc931e2f8adb43924b0e38b9c46f83c7`. Исследовательская копия, без production интеграции. Архитектура уже параметризована по размерам. Конвертер переводит MLX F16 обратно в PyTorch-compatible Conv1d layout, 75 transposes, 824 tensors, сохраняя 71-class CTC и multilingual vocabulary. Norm/bias/frontend tensors F32. Исходный manifest, upstream revision и hashes сохранены в conversion.json.','','Короткий input sample-022 22.72s целиком подан в обе floating реализации. MLX использует F16 activations, ggml F32 activations. Text equality: '+str(parity['text_equal'])+'. Logits cosine: '+str(parity['tensors']['raw_logits']['cosine'])+'. Argmax agreement: '+str(parity['tensors']['raw_logits']['argmax_frame_agreement'])+'. Метрики mel/encoder/logits и дампы сохранены в parity.json, reference/, smoke-f16/dump/.','','## Политика длинного аудио','','`whole` использует один encoder pass на запись. Research-only env `TRANSCRIBE_GIGAAM_WHOLE_INPUT=1` включён только для multilingual variant, он обходит stock window planner. Максимальная запись корпуса 81.152s. `stock25` использует исходный planner 25s с 2s context по краям, затем encoder stitching и один greedy decode. Сопоставимая MLX reference тоже whole, chunk_seconds120/overlap0. Stock25 и whole нельзя смешивать при оценке fidelity переноса.','','## Воспроизведение','','```sh','uv --native-tls run --no-project --python 3.13 --with gguf --with safetensors --with numpy python convert_mlx.py','DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uv --native-tls run --no-project --python 3.13 --with cmake python build_runtime.py','uv --native-tls run --no-project --python 3.13 --with numpy --with soundfile python benchmark.py smoke-f16','uv --native-tls run --no-project --python 3.13 --with gigaam-multilingual-mlx==0.2.0 --with soundfile python run_reference.py','uv --native-tls run --no-project --python 3.13 --with numpy python parity.py','uv --native-tls run --no-project --python 3.13 --with numpy --with soundfile python benchmark.py f16-whole','uv --native-tls run --no-project --python 3.13 --with numpy --with soundfile python benchmark.py f16-stock25','uv --native-tls run --no-project --python 3.13 --with jiwer --with numpy python score.py','```','','## Ограничения','','Исторические baseline timing не чередовались с этим экспериментом. Reference transcripts приняты пользователем, а не независимо размечены; два unclear markers влияют на corpus errors. Корпус преимущественно русский и не проверяет полноценное multilingual качество. Один short tensor parity smoke не гарантирует численное совпадение на любом входе, поэтому дополнительно приведён полный floating corpus. Q8 является новой GGUF quantization F16 source, а не импортом MLX INT8 group64. Исходная all-target сборка tools=ON/examples=OFF упала на upstream transcribe-bench missing wav.h; targeted transcribe/transcribe-quantize собраны отдельно, см. build-process.json. Нет CoreML. Все inference процессы имеют конечный timeout и сохраняют exit codes.']
(r/'report.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({n:{k:s[k] for k in ['original','hesitations_removed','median_native_s','corpus_sum_recording_medians_s']} for n,s in summaries.items()},ensure_ascii=False,indent=2))
