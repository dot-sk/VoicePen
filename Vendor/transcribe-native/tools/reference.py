"""Matched-F32 independent stock-window MLX oracle and all-block reference export."""
import argparse
import json
from pathlib import Path
import mlx.core as mx
import numpy as np
import soundfile as sf
from gigaam_multilingual_mlx import load_model
from parity import collapse,window_plan
from prepare import sha256,ROOT


def infer(model,audio,whole=False,export=None):
    features,lengths=model.preprocessor(mx.array(audio)[None,:],mx.array([len(audio)],dtype=mx.int32))
    mx.eval(features,lengths)
    mel_frames=int(lengths[0].item())
    total=(mel_frames+3)//4
    windows=[(0,total,0,total)] if whole else window_plan(total)
    retained=[]
    spans=[]
    for index,(a,b,ws,we) in enumerate(windows):
        m0=4*ws
        mlen=mel_frames-m0 if we==total else 4*(we-ws)
        f=features[:,m0:m0+mlen,:]
        x,lens=model.encoder.pre_encode(f,mx.array([mlen],dtype=mx.int32))
        if export:
            folder=export/f'window-{index:03d}';folder.mkdir(parents=True,exist_ok=True)
            np.save(folder/'mel.npy',np.asarray(f).squeeze(0))
            np.save(folder/'subsample.npy',np.asarray(x).squeeze(0))
        cos,sin=model.encoder._rotary(x.shape[1],x.dtype)
        padding_mask=~(mx.arange(x.shape[1])[None,:]<lens[:,None])
        for i,layer in enumerate(model.encoder.layers):
            x=layer(x,cos,sin,None,padding_mask)
            if export:
                mx.eval(x);np.save(folder/f'block{i}.npy',np.asarray(x).squeeze(0))
        mx.eval(x)
        if int(lens[0].item())!=we-ws: raise ValueError('reference encoder length mismatch')
        retained.append(x[:,a-ws:b-ws,:])
        spans.append({'retained':[a,b],'encoded':[ws,we],'mel':[m0,m0+mlen],'positions':'window-local'})
    encoded=mx.concatenate(retained,axis=1)
    logits=model.head.decoder(encoded)
    mx.eval(encoded,logits)
    ids=collapse(np.asarray(mx.argmax(logits,axis=-1)).reshape(-1),70)
    if export:
        np.save(export/'encoder.npy',np.asarray(encoded).squeeze(0))
        np.save(export/'logits.npy',np.asarray(logits).squeeze(0))
    text=model.greedy_decode(logits,mx.array([total],dtype=mx.int32))[0]['text']
    return {'text':text,'token_ids':ids,'encoder_frames':total,'windows':spans,'window_policy':'whole-input-diagnostic' if whole else 'stock25-v1','activations':'F32','logical_weights':'F16 values promoted to F32'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,required=True)
    p.add_argument('--dataset',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--export-id',default='sample-022')
    p.add_argument('--whole',action='store_true')
    a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    pins=json.loads((ROOT/'pins.json').read_text())
    if sha256(a.dataset)!=pins['evaluation_inputs']['dataset_sha256'] or sha256(a.model/'model.safetensors')!=pins['model']['weights_sha256'] or sha256(a.model/'config.json')!=pins['model']['config_sha256']:
        raise ValueError('reference input pin mismatch')
    dataset=json.loads(a.dataset.read_text())
    model=load_model(a.model,local_files_only=True,dtype='float32');model.set_dtype(mx.float32);mx.eval(model.parameters())
    (a.output/'metadata.json').write_text(json.dumps({'role':'matched-window-F32-oracle','dataset_sha256':sha256(a.dataset),'model_sha256':sha256(a.model/'model.safetensors'),'config_sha256':sha256(a.model/'config.json'),'window_policy':'whole-input-diagnostic' if a.whole else 'stock25-v1','reference_sha256':sha256(__file__)},indent=2)+'\n')
    with (a.output/'runs.jsonl').open('x') as out:
        for entry in dataset['entries']:
            path=a.dataset.parent/entry['audio']
            if sha256(path)!=entry['sha256']: raise ValueError('audio digest mismatch: '+entry['id'])
            audio,sr=sf.read(path,dtype='float32')
            if sr!=16000 or audio.ndim!=1 or len(audio)!=round(entry['duration']*16000) or not np.isfinite(audio).all(): raise ValueError('audio geometry')
            row={'sample_id':entry['id'],**infer(model,audio,a.whole,a.output/'tensors'/entry['id'] if entry['id']==a.export_id else None)}
            out.write(json.dumps(row,ensure_ascii=False)+'\n');out.flush()
            print(entry['id'],'ok',len(row['windows']),flush=True)
