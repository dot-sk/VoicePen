import json
from pathlib import Path
import numpy as np
r=Path(__file__).resolve().parent;d=r/'smoke-f16/dump';ref=r/'reference'
result=json.loads((ref/'result.json').read_text());out={'sample_id':result['sample_id'],'input_policy':'same complete 22.72s float32 WAV, no windows; matching F16 weights; MLX F16 activations versus ggml F32 activations','text_equal':result['mlx']['text'].strip()==result['cpp']['text'].strip(),'mlx_text':result['mlx']['text'],'cpp_text':result['cpp']['text'],'tensors':{}}
for name,native,reference in [('mel','frontend.mel.out','mel'),('encoder','dec.enc_out','encoder'),('raw_logits','ctc.logits.raw','raw_logits'),('log_probs','ctc.log_probs','log_probs')]:
 meta=json.loads((d/(native+'.json')).read_text());a=np.fromfile(d/(native+'.f32'),dtype=np.float32).reshape(meta['shape']);b=np.load(ref/(reference+'.npy')).squeeze(0)
 if name=='mel':a=a.T
 assert a.shape==b.shape,(name,a.shape,b.shape)
 x=a.astype(np.float64).ravel();y=b.astype(np.float64).ravel();delta=x-y
 metric={'shape':list(a.shape),'max_abs':float(np.abs(delta).max()),'mean_abs':float(np.abs(delta).mean()),'rmse':float(np.sqrt(np.mean(delta**2))),'cosine':float(np.dot(x,y)/np.sqrt(np.dot(x,x)*np.dot(y,y)))}
 if 'logit' in name or name=='log_probs':metric['argmax_frame_agreement']=float(np.mean(a.argmax(-1)==b.argmax(-1)))
 out['tensors'][name]=metric
assert out['text_equal'],out
assert out['tensors']['raw_logits']['cosine']>.99,out
(r/'parity.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False,indent=2))
