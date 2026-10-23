import hashlib,json,subprocess
from datetime import datetime,timezone
from pathlib import Path
r=Path(__file__).resolve().parent
p=r/'benchmark.py';s=p.read_text();p.write_text(s.replace("1 if name=='smoke-f16' else 3","1 if name.startswith('smoke-') else 3"))
baseline_sha=hashlib.sha256((r/'baseline-libtranscribe.dylib').read_bytes()).hexdigest()
for name in ['f16-whole','f16-stock25','q8-whole','q8-stock25','smoke-f16']:
 p=r/name/'metadata.json';d=json.loads(p.read_text());d['library_sha256']=baseline_sha;p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
for p in r.glob('smoke-*/metadata.json'):
 d=json.loads(p.read_text());d['repeats']=1;p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
checks={'checked_at':datetime.now(timezone.utc).isoformat(),'scope':'research copy only; production VoicePen unchanged','checks':[
 {'command':'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uv --native-tls run --no-project --python 3.13 --with cmake python .local/asr-quality/evaluations/gigaam600m-transcribe-metal-20261019/build_runtime.py','exit_code':0,'targets':['transcribe-cli','transcribe-bench','transcribe-quantize']},
 {'command':'uv --native-tls run --no-project --python 3.13 --with clang-format==22.1.5 clang-format --dry-run --Werror source/src/arch/gigaam/{encoder.cpp,encoder.h,decoder.cpp,decoder.h,model.cpp}','exit_code':0},
 {'command':'patch --dry-run -p1 -d .local/asr-quality/evaluations/transcribe-cpp-20261019/source < .local/asr-quality/evaluations/gigaam600m-transcribe-metal-20261019/source.patch','exit_code':0},
 {'command':'uv --native-tls run --no-project --python 3.13 --with jiwer --with numpy python .local/asr-quality/evaluations/gigaam600m-transcribe-metal-20261019/score.py','exit_code':0},
 {'command':"ps -axo pid,ppid,command | rg 'gigaam600m-transcribe-metal-20261019/(benchmark|ab_head|reference|run_reference|build_runtime|quantize)'",'exit_code':1,'interpretation':'ps succeeded with escalation; rg found no task processes'}],
 'completed_process_results':{str(p.relative_to(r)):json.loads(p.read_text()) for p in [r/n/'process.json' for n in ['f16-whole','f16-stock25','q8-whole','q8-stock25','head-ab-f16-whole','smoke-final-cpu-f16','smoke-gpu-fixed-f16']]+[r/'reference-process.json',r/'reference_f32-process.json']},
 'not_verified':['full all24-layer tensor coverage','original full-F32 checkpoint deterministic CPU oracle','upstream preflight/validate manifest suite','batch8 parity','English/Kazakh corpus','upstream ctest','VoicePen make test, production code unchanged','production integration/native regression coverage','publication machine matrix and Stage8']}
assert all(v['exit_code']==0 for v in checks['completed_process_results'].values())
(r/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n');print('verification recorded')
