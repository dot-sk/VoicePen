"""Run the C client on every frozen input with bounded processes and saved backend proof."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import soundfile as sf
import numpy as np
from evaluate import verify_dataset
from prepare import sha256,ROOT
from run import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['client','model','dataset','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--package',type=Path)
    a=p.parse_args()
    pins=json.loads((ROOT/'pins.json').read_text())
    entries=verify_dataset(a.dataset,pins.get('evaluation_inputs',{}).get('dataset_sha256'))
    a.output.mkdir(parents=True,exist_ok=False)
    metadata={'role':'native-F16','window_policy':'stock25-v1','model_sha256':sha256(a.model),'client_sha256':sha256(a.client),'dataset_sha256':sha256(a.dataset),'threads':4,'repeats':3,'warmup':'one same-shape input before each recording; excluded','platform':platform.platform(),'architecture':platform.machine(),'stage_placement':{'frontend':'host','encoder':'Metal','ctc_projection':'host','ctc_search':'host'},'pins':pins}
    if a.package:
        from package import verify
        manifest=verify(a.package)
        if manifest['model']['gguf_sha256']!=metadata['model_sha256']:raise ValueError('package/model pair mismatch')
        metadata['package_manifest_sha256']=sha256(a.package/'manifest.json')
        metadata['runtime_sha256']=sha256(a.package/'VoicePenGigaAM.framework/Versions/A/VoicePenGigaAM')
    (a.output/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    with (a.output/'runs.jsonl').open('x') as output:
        for e in entries:
            audio,sr=sf.read(a.dataset.parent/e['audio'],dtype='float32')
            if not np.isfinite(audio).all():raise ValueError('nonfinite input')
            pcm=a.output/(e['id']+'.f32');audio.tofile(pcm)
            log=a.output/(e['id']+'.log')
            try:run([a.client.resolve(),a.model.resolve(),pcm.resolve(),'3'],log,180)
            finally:pcm.unlink(missing_ok=True)
            text=log.read_text()
            if 'encoder=Metal arithmetic_nodes=' not in text:raise ValueError('missing encoder graph placement proof')
            rows=[json.loads(line) for line in text.splitlines() if line.startswith('{"repeat"')]
            if len(rows)!=3:raise ValueError('incomplete recording calls')
            for row in rows:
                if row['status'] or row['sample_count']!=len(audio):raise ValueError('failed or truncated call')
                output.write(json.dumps({'sample_id':e['id'],**row},ensure_ascii=False)+'\n')
            output.flush()
            print(e['id'],'ok','median',round(statistics.median(r['native_wall_s'] for r in rows),4),flush=True)
