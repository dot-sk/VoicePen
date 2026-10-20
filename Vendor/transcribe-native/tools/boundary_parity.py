"""Speech parity immediately below/at/above the native 625-frame boundary."""
import argparse
import json
import os
from pathlib import Path
import re
import mlx.core as mx
import numpy as np
import soundfile as sf
from gigaam_multilingual_mlx import load_model
from prepare import ROOT,sha256
from reference import infer
from parity import compare
from run import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['model','gguf','client','dataset','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    pins=json.loads((ROOT/'pins.json').read_text())
    if sha256(a.dataset)!=pins['evaluation_inputs']['dataset_sha256']:raise ValueError('dataset pin mismatch')
    entry=next(e for e in json.loads(a.dataset.read_text())['entries'] if e['id']=='sample-022')
    audio=a.dataset.parent/entry['audio']
    if sha256(audio)!=entry['sha256']:raise ValueError('source audio pin mismatch')
    speech,sr=sf.read(audio,dtype='float32')
    if sr!=16000 or speech.ndim!=1:raise ValueError('source audio geometry')
    model=load_model(a.model,local_files_only=True,dtype='float32');model.set_dtype(mx.float32);mx.eval(model.parameters())
    reports=[]
    for frames in [624,625,626]:
        count=640*frames+160
        if count<len(speech):raise ValueError('speech would be truncated')
        samples=np.concatenate([np.zeros(count-len(speech),dtype=np.float32),speech])
        folder=a.output/str(frames);folder.mkdir()
        reference=infer(model,samples,export=folder/'reference')
        if reference['encoder_frames']!=frames:raise ValueError('wrong boundary fixture length')
        (folder/'reference.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
        pcm=folder/'input.f32';samples.tofile(pcm)
        dump=folder/'dump';dump.mkdir()
        run([a.client.resolve(),a.gguf.resolve(),pcm.resolve(),'1'],folder/'native.log',180,env={**os.environ,'TRANSCRIBE_DUMP_DIR':str(dump.resolve())})
        log=(folder/'native.log').read_text()
        row=next(json.loads(line) for line in log.splitlines() if line.startswith('{"repeat"'))
        meta=json.loads((dump/'ctc.logits.raw.json').read_text())
        native=np.fromfile(dump/'ctc.logits.raw.f32',dtype=np.float32).reshape(meta['shape'])
        metrics=compare(native,np.load(folder/'reference/logits.npy'),'logits','F16')
        token_equal=row['token_ids']==reference['token_ids']
        spans=[tuple(map(int,m)) for m in re.findall(r'stock25 window=(\d+) retained=(\d+):(\d+) encoded=(\d+):(\d+) mel=(\d+):(\d+)',log)]
        expected=[(i,*window['retained'],*window['encoded'],*window['mel']) for i,window in enumerate(reference['windows'])]
        spans_equal=frames<=625 or spans[:len(expected)]==expected
        report={'encoder_frames':frames,'sample_count':len(samples),'window_policy':'stock25-v1','windows':reference['windows'],'native_spans_equal':spans_equal,'exact_collapsed_token_ids':token_equal,'logits':metrics,'pass':row['status']==0 and native.shape[0]==frames and metrics['pass'] and token_equal and spans_equal}
        reports.append(report);print(frames,report['pass'],flush=True)
    (a.output/'report.json').write_text(json.dumps({'pass':all(r['pass'] for r in reports),'source_sample':'sample-022','source_audio_sha256':entry['sha256'],'source_weights_sha256':sha256(a.model/'model.safetensors'),'native_model_sha256':sha256(a.gguf),'cases':reports},indent=2)+'\n')
    if not all(r['pass'] for r in reports):raise SystemExit(1)
