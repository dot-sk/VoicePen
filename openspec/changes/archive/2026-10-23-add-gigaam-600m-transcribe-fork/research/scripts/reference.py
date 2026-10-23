import json, time
from pathlib import Path
import mlx.core as mx
import numpy as np
import soundfile as sf
from gigaam_multilingual_mlx import load_model
ROOT=Path(__file__).resolve().parent
run=json.loads((ROOT/'smoke-f16/runs.jsonl').read_text().splitlines()[0]);corpus=json.loads((ROOT.parent/'gigaam-20261019/corpus.json').read_text())
clip=next(c for c in corpus['selected'] if c['sample_id']==run['sample_id']);audio,sr=sf.read(clip['selected_audio_path'],dtype='float32');assert sr==16000
model=load_model(ROOT.parent/'gigaam-20261019/models/fp16',local_files_only=True)
x=mx.array(audio)[None,:];lengths=mx.array([len(audio)],dtype=mx.int32)
f,fl=model.preprocessor(x,lengths);e,el=model.encoder(f.astype(mx.float16),fl);raw=model.head.decoder(e);lp=model.head(e);mx.eval(f,e,raw,lp)
d=ROOT/'reference';d.mkdir(exist_ok=True)
for n,a in [('mel',f),('encoder',e),('raw_logits',raw),('log_probs',lp)]:np.save(d/(n+'.npy'),np.asarray(a).astype(np.float32))
text=model.greedy_decode(lp,el)[0];(d/'result.json').write_text(json.dumps({'sample_id':run['sample_id'],'mlx':text,'cpp':run,'length':int(np.asarray(el)[0])},ensure_ascii=False,indent=2)+'\n');print(json.dumps(text,ensure_ascii=False))
from gigaam_multilingual_mlx import service
import os
service.load_audio=lambda path,sample_rate=16000:sf.read(path,dtype='float32')[0]
folder=ROOT/'mlx-f16-whole';folder.mkdir(exist_ok=True)
warmup=service.transcribe_file(model,corpus['selected'][0]['selected_audio_path'],chunk_seconds=120,overlap_seconds=0)
(folder/'metadata.json').write_text(json.dumps({'backend':'MLX Metal','weights':'same MLX F16 artifact as GGUF conversion','warmup':warmup['metrics'],'chunk_seconds':120,'overlap_seconds':0,'repeats':3},indent=2)+'\n')
with (folder/'runs.jsonl').open('x') as out:
 for clip in corpus['selected']:
  for repeat in range(3):
   r=service.transcribe_file(model,clip['selected_audio_path'],chunk_seconds=120,overlap_seconds=0)
   assert len(r['chunks'])==1
   row={'sample_id':clip['sample_id'],'repeat':repeat,'status':0,'text':r['text'],'sample_count':round(r['duration_seconds']*16000),'audio_duration_s':r['duration_seconds'],'native_wall_s':r['metrics']['wall_seconds'],'metrics':r['metrics']}
   out.write(json.dumps(row,ensure_ascii=False)+'\n');out.flush();os.fsync(out.fileno());print('mlx-f16',clip['sample_id'],repeat,row['native_wall_s'],flush=True)
