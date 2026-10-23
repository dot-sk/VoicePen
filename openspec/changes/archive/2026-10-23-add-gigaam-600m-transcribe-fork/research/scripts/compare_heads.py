import json
from pathlib import Path
import numpy as np
r=Path(__file__).resolve().parent
names=['smoke-final-cpu-f16','smoke-gpu-fixed-f16'];arrays=[];rows=[]
for name in names:
 d=r/name/'dump';shape=json.loads((d/'ctc.logits.raw.json').read_text())['shape'];arrays.append(np.fromfile(d/'ctc.logits.raw.f32',dtype=np.float32).reshape(shape));rows.append(json.loads((r/name/'runs.jsonl').read_text().splitlines()[0]))
a,b=arrays;assert a.shape==b.shape
x,y=a.astype(np.float64).ravel(),b.astype(np.float64).ravel();delta=x-y
out={'sample_id':rows[0]['sample_id'],'same_final_library':True,'text_equal':rows[0]['text']==rows[1]['text'],'shape':list(a.shape),'max_abs':float(np.abs(delta).max()),'mean_abs':float(np.abs(delta).mean()),'rmse':float(np.sqrt(np.mean(delta**2))),'nrmse':float(np.sqrt(np.mean(delta**2))/np.sqrt(np.mean(x**2))),'cosine':float(np.dot(x,y)/np.sqrt(np.dot(x,x)*np.dot(y,y))),'argmax_frame_agreement':float(np.mean(a.argmax(-1)==b.argmax(-1))),'cpu_text':rows[0]['text'],'gpu_text':rows[1]['text']}
(r/'head-logit-parity.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False,indent=2));assert out['text_equal'] and out['argmax_frame_agreement']==1
