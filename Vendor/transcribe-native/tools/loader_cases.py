"""Direct C-loader rejection fixtures, including finite-valued payload corruption."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
from gguf import GGUFReader
from run import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['client','model','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    reader=GGUFReader(str(a.model))
    base=reader.data.ctypes.data
    def offset(key):return reader.fields[key].parts[-1].ctypes.data-base
    scalar_cases=[('profile_version',offset('stt.gigaam.profile_version'),struct.pack('<I',99)),('blank_identity',offset('tokenizer.ggml.blank_token_id'),struct.pack('<I',69)),('source_digest',offset('stt.gigaam.source_weights_sha256'),b'0')]
    tensor=next(t for t in reader.tensors if t.name=='head.ctc.bias')
    payload_offset=tensor.data.ctypes.data-base
    with a.model.open('rb') as f:f.seek(payload_offset);byte=f.read(1)
    scalar_cases.append(('finite_tensor_payload',payload_offset,bytes([byte[0]^1])))
    cases=[]
    for name,where,replacement in scalar_cases:
        model=a.output/(name+'.gguf')
        result=subprocess.run(['cp','-c',str(a.model),str(model)],capture_output=True)
        if result.returncode:shutil.copyfile(a.model,model)
        try:
            with model.open('r+b') as f:f.seek(where);f.write(replacement)
            process=run([a.client.resolve(),model.resolve(),'unused','--expect-load-failure'],a.output/(name+'.log'),120)
            cases.append({'case':name,'pass':True,'process':process})
        finally:model.unlink(missing_ok=True)
    env={**os.environ,'TRANSCRIBE_BACKENDS':'cpu'}
    process=run([a.client.resolve(),a.model.resolve(),'unused','--expect-backend-failure'],a.output/'required-metal-unavailable.log',120,env=env)
    cases.append({'case':'required_metal_unavailable','pass':True,'process':process})
    report={'pass':all(c['pass'] for c in cases),'cases':cases}
    (a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'pass':report['pass'],'cases':len(cases)}))
