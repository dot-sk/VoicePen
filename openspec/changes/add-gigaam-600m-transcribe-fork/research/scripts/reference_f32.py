from dataclasses import replace
import json
from pathlib import Path
import mlx.core as mx
import numpy as np
import soundfile as sf
from gigaam_multilingual_mlx import load_model
r=Path(__file__).resolve().parent
smoke=r/'smoke-instrumented-f16'
run=json.loads((smoke/'runs.jsonl').read_text().splitlines()[0]);corpus=json.loads((r.parent/'gigaam-20261019/corpus.json').read_text());clip=next(c for c in corpus['selected'] if c['sample_id']==run['sample_id']);audio,sr=sf.read(clip['selected_audio_path'],dtype='float32');assert sr==16000
model=load_model(r.parent/'gigaam-20261019/models/fp16',local_files_only=True,dtype='float32');model.set_dtype(mx.float32);mx.eval(model.parameters())
x=mx.array(audio)[None,:];lengths=mx.array([len(audio)],dtype=mx.int32);features,fl=model.preprocessor(x,lengths);encoded,el=model.encoder(features,fl);raw=model.head.decoder(encoded);lp=model.head(encoded);mx.eval(features,encoded,raw,lp)
ref={'mel':features,'encoder':encoded,'raw_logits':raw,'log_probs':lp}
x,lens=model.encoder.pre_encode(features,fl);ref['subsample']=x;cos,sin=model.encoder._rotary(x.shape[1],x.dtype)
valid=mx.arange(x.shape[1])[None,:]<lens[:,None];padding_mask=~valid
for i,layer in enumerate(model.encoder.layers):
 if i==0:
  x=x+.5*layer.feed_forward1(layer.norm_feed_forward1(x));x=x+layer.self_attn(layer.norm_self_att(x),cos,sin,None);ref['block0_after_attn']=x;x=x+layer.conv(layer.norm_conv(x),padding_mask);ref['block0_after_conv']=x;x=x+.5*layer.feed_forward2(layer.norm_feed_forward2(x));x=layer.norm_out(x)
 else:x=layer(x,cos,sin,None,padding_mask)
 if i in {0,11,23}:ref[f'block{i}']=x
mx.eval(list(ref.values()));folder=r/'reference-f32';folder.mkdir(exist_ok=True)
for n,a in ref.items():assert a.dtype==mx.float32,(n,a.dtype);np.save(folder/(n+'.npy'),np.asarray(a))
mapping={'mel':'frontend.mel.out','subsample':'enc.subsample.out','block0_after_attn':'enc.block.0.after_attn','block0_after_conv':'enc.block.0.after_conv','block0':'enc.block.0.out','block11':'enc.block.11.out','block23':'enc.block.23.out','encoder':'dec.enc_out','raw_logits':'ctc.logits.raw','log_probs':'ctc.log_probs'}
result={'sample_id':run['sample_id'],'text':model.greedy_decode(lp,el)[0]['text'],'weights':'same F16-valued source weights promoted to F32 in MLX; native GGUF F16 kernels and F32 norm/bias','activations':'MLX explicitly all F32, native ggml F32','tensors':{}}
for n,dump in mapping.items():
 meta=json.loads((smoke/'dump'/(dump+'.json')).read_text());a=np.fromfile(smoke/'dump'/(dump+'.f32'),dtype=np.float32).reshape(meta['shape']).squeeze();b=np.asarray(ref[n]).squeeze(0)
 if n=='mel':a=a.T
 assert a.shape==b.shape,(n,a.shape,b.shape)
 a=a.astype(np.float64).ravel();b=b.astype(np.float64).ravel();delta=a-b;rmse=float(np.sqrt(np.mean(delta**2)));nrmse=rmse/float(np.sqrt(np.mean(b**2)));cosine=float(np.dot(a,b)/np.sqrt(np.dot(a,a)*np.dot(b,b)))
 result['tensors'][n]={'max_abs':float(np.abs(delta).max()),'mean_abs':float(np.abs(delta).mean()),'rmse':rmse,'nrmse':nrmse,'cosine':cosine,'f32_gate_pass':cosine>=.99999 and nrmse<=.001}
result['text_equal']=result['text'].strip()==run['text'].strip();result['all_f32_diagnostic_gates_pass']=all(t['f32_gate_pass'] for t in result['tensors'].values())
(r/'parity-f32-activations.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2),flush=True)
differences=json.loads((r/'floating-text-differences.json').read_text());diagnostics=[]
for case in differences:
 clip=next(c for c in corpus['selected'] if c['sample_id']==case['sample_id']);audio,sr=sf.read(clip['selected_audio_path'],dtype='float32');assert sr==16000
 lp,lens=model(mx.array(audio));mx.eval(lp,lens);text=model.greedy_decode(lp,lens)[0]['text']
 diagnostics.append({**case,'mlx_f32':text,'matches_cpp':text.strip()==case['cpp'].strip()})
(r/'floating-difference-f32-diagnostics.json').write_text(json.dumps(diagnostics,ensure_ascii=False,indent=2)+'\n');print(json.dumps(diagnostics,ensure_ascii=False,indent=2),flush=True)
native={case['sample_id']:case['text'] for case in [json.loads(line) for line in (r/'f16-whole/runs.jsonl').read_text().splitlines()] if case['repeat']==0}
full=[]
for clip in corpus['selected']:
 audio,sr=sf.read(clip['selected_audio_path'],dtype='float32');assert sr==16000
 lp,lens=model(mx.array(audio));mx.eval(lp,lens);text=model.greedy_decode(lp,lens)[0]['text']
 full.append({'sample_id':clip['sample_id'],'mlx_f32':text,'cpp':native[clip['sample_id']],'text_equal':text.strip()==native[clip['sample_id']].strip()})
(r/'floating-full-corpus-f32-text-parity.json').write_text(json.dumps({'count':len(full),'matching':sum(case['text_equal'] for case in full),'rows':full},ensure_ascii=False,indent=2)+'\n');print('matched full corpus',sum(case['text_equal'] for case in full),'/',len(full),flush=True)
