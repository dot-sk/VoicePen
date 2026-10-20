"""Every-block parity on deterministic synthetic and five licensed speech fixtures."""
import argparse
import json
import os
from pathlib import Path
import mlx.core as mx
import numpy as np
import soundfile as sf
from gigaam_multilingual_mlx import load_model
from compare_stages import compare_directory
from prepare import ROOT,sha256
from reference import infer
from run import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['model','gguf','client','speech','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--storage',choices=['F16','F32'],required=True)
    p.add_argument('--backend',choices=['Metal','CPU'],default='Metal')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    fixture_manifest=json.loads((ROOT/'fixtures/public-speech.json').read_text())
    if {e['id'] for e in fixture_manifest['entries']}!={'ru','en','kk','ky','uz'}:raise ValueError('incomplete language fixtures')
    cases=[]
    for entry in fixture_manifest['entries']:
        path=a.speech/entry['audio']
        if sha256(path)!=entry['sha256']:raise ValueError('speech fixture digest mismatch')
        audio,sr=sf.read(path,dtype='float32')
        if sr!=16000 or audio.ndim!=1:raise ValueError('speech geometry')
        cases.append((entry['id'],audio,True))
    impulse=np.zeros(16000,dtype=np.float32);impulse[8000]=1
    cases += [('silence',np.zeros(16000,dtype=np.float32),True),('impulse',impulse,False),('seeded-noise',np.random.default_rng(600).normal(0,.01,16000).astype(np.float32),False)]
    model=load_model(a.model,local_files_only=True,dtype='float32');model.set_dtype(mx.float32);mx.eval(model.parameters())
    reports=[]
    for name,audio,require_tokens in cases:
        folder=a.output/name;folder.mkdir()
        reference=infer(model,audio,export=folder/'reference')
        pcm=folder/'input.f32';audio.tofile(pcm)
        dump=folder/'dump';dump.mkdir()
        env={**os.environ,'TRANSCRIBE_DUMP_DIR':str(dump.resolve()),'TRANSCRIBE_DUMP_ALL_BLOCKS':'1'}
        run([a.client.resolve(),a.gguf.resolve(),pcm.resolve(),'1',a.backend],folder/'native.log',120,env=env)
        rows=[json.loads(line) for line in (folder/'native.log').read_text().splitlines() if line.startswith('{"repeat"')]
        actual_backend=next(json.loads(line)['actual_backend'] for line in (folder/'native.log').read_text().splitlines() if line.startswith('{"actual_backend"'))
        if not actual_backend.startswith('MTL' if a.backend=='Metal' else 'CPU'):raise ValueError('unexpected actual encoder backend')
        if len(rows)!=1 or rows[0]['status']!=0:raise ValueError('fixture native request failed')
        report=compare_directory(dump,folder/'reference',a.storage,require_tokens=require_tokens)
        report['fixture']=name
        report['actual_backend']=actual_backend
        report['native_token_ids_equal_reference']=rows[0]['token_ids']==reference['token_ids']
        if require_tokens:report['pass']=report['pass'] and report['native_token_ids_equal_reference']
        if name=='silence':report['pass']=report['pass'] and rows[0]['text']==''
        (folder/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        reports.append(report);print(name,report['pass'],flush=True)
    aggregate={'pass':all(r['pass'] for r in reports),'storage':a.storage,'requested_encoder_backend':a.backend,'source_weights_sha256':sha256(a.model/'model.safetensors'),'model_sha256':sha256(a.gguf),'client_sha256':sha256(a.client),'fixtures':[{'name':r['fixture'],'pass':r['pass'],'actual_backend':r['actual_backend'],'exact_collapsed_token_ids':r['exact_collapsed_token_ids']} for r in reports]}
    (a.output/'report.json').write_text(json.dumps(aggregate,indent=2)+'\n')
    if not aggregate['pass']:raise SystemExit(1)
