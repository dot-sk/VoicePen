"""Compare every saved encoder block, without treating sampled blocks as full coverage."""
import argparse
import json
from pathlib import Path
import numpy as np
from parity import compare,collapse


def compare_directory(native,reference,storage,require_tokens=True):
    mappings=[('mel','frontend.mel.out','window-000/mel.npy'),('subsample','enc.subsample.out','window-000/subsample.npy')]
    mappings += [(f'block{i}',f'enc.block.{i}.out',f'window-000/block{i}.npy') for i in range(24)]
    mappings += [('encoder','dec.enc_out','encoder.npy'),('logits','ctc.logits.raw','logits.npy')]
    results=[]
    for stage,name,ref in mappings:
        try:
            meta=json.loads((native/(name+'.json')).read_text())
            x=np.fromfile(native/(name+'.f32'),dtype=np.float32).reshape(meta['shape']).squeeze()
            y=np.load(reference/ref)
            if stage=='mel':x=x.T
            results.append(compare(x,y,stage,storage))
        except (FileNotFoundError,ValueError) as error:
            results.append({'stage':stage,'pass':False,'reason':str(error)})
    try:
        logits=np.fromfile(native/'ctc.logits.raw.f32',dtype=np.float32).reshape(-1,71)
        ref=np.load(reference/'logits.npy')
        tokens_equal=collapse(np.argmax(logits,axis=-1),70)==collapse(np.argmax(ref,axis=-1),70)
    except (FileNotFoundError,ValueError):tokens_equal=False
    return {'pass':all(x['pass'] for x in results) and (tokens_equal or not require_tokens),'storage':storage,'activations':'F32','checkpoints':results,'exact_collapsed_token_ids':tokens_equal,'token_equality_required':require_tokens,'encoder_blocks_checked':24}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--storage',choices=['F16','F32'],required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();result=compare_directory(a.native,a.reference,a.storage)
    a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'pass':result['pass'],'exact_collapsed_token_ids':result['exact_collapsed_token_ids'],'failures':[x for x in result['checkpoints'] if not x['pass']]},indent=2))
    if not result['pass']:raise SystemExit(1)
