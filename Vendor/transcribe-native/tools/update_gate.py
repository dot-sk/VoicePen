"""Fail closed unless every applicable dependency acceptance report is present and passing."""
import argparse
import hashlib
import json
from pathlib import Path
from package import verify
from prepare import ROOT,sha256

REQUIRED={'contracts','loader','boundary','numerical_f16','numerical_f32','speech_languages','corpus','package_clients','reproducibility','existing_v3_profiles','upstream_suite','licenses'}


def validation_inputs_sha256():
    inputs=[ROOT/name for name in ['pins.json','model-config.json','tensor-schema.json']]
    for folder in ['tools','tests','patches','schema','fixtures','licenses']:
        inputs.extend(path for path in (ROOT/folder).rglob('*') if path.is_file() and '__pycache__' not in path.parts)
    hashes={str(path.relative_to(ROOT)):sha256(path) for path in sorted(inputs)}
    return hashlib.sha256(json.dumps(hashes,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def validate(root,reports):
    manifest=verify(root)
    if set(reports)!=REQUIRED:raise ValueError('missing or unknown acceptance reports: '+repr(sorted(REQUIRED-set(reports))))
    evidence={}
    inputs_sha256=validation_inputs_sha256()
    for gate,path in reports.items():
        data=json.loads(path.read_text())
        if data.get('pass') is not True:raise ValueError('acceptance gate failed: '+gate)
        if data.get('candidate_manifest_sha256')!=sha256(root/'manifest.json'):raise ValueError('report is for a different dependency pin: '+gate)
        if data.get('validation_inputs_sha256')!=inputs_sha256:raise ValueError('report predates current converter/reference/validation inputs: '+gate)
        evidence[gate]={'path':str(path),'sha256':sha256(path)}
    return {'pass':True,'candidate':manifest['candidate'],'manifest_sha256':sha256(root/'manifest.json'),'validation_inputs_sha256':inputs_sha256,'evidence':evidence}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--reports',type=Path,required=True,help='JSON object of gate name to immutable local report path')
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();reports={k:Path(v) for k,v in json.loads(a.reports.read_text()).items()}
    a.output.write_text(json.dumps(validate(a.package,reports),indent=2)+'\n')
