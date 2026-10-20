"""Export promotion edits against an upstream tree with the preserved research patch applied."""
import argparse
import json
from pathlib import Path
import subprocess
from prepare import ROOT,sha256

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base',type=Path,required=True)
    p.add_argument('--source',type=Path,required=True)
    a=p.parse_args();parts=[]
    for path in sorted(a.source.rglob('*')):
        if not path.is_file() or path.is_symlink():continue
        relative=path.relative_to(a.source)
        if relative.parts[0] not in {'src','ggml','tools','include'} and str(relative) not in {'CMakeLists.txt','voicepen.exports'}:continue
        baseline=a.base/relative
        if baseline.exists() and baseline.read_bytes()==path.read_bytes():continue
        result=subprocess.run(['diff','-u','--label','a/'+str(relative) if baseline.exists() else '/dev/null','--label','b/'+str(relative),str(baseline) if baseline.exists() else '/dev/null',str(path)],capture_output=True,text=True)
        if result.returncode not in {0,1}:raise RuntimeError(result.stderr)
        parts.append(result.stdout)
    patch=ROOT/'patches/0002-supported-profile-and-isolation.patch';patch.write_text(''.join(parts))
    pins=json.loads((ROOT/'pins.json').read_text())
    provenance={'upstream':pins['upstream'],'patches':[{'path':path.name,'sha256':sha256(path)} for path in sorted((ROOT/'patches').glob('*.patch'))]}
    (a.source/'VOICEPEN_SOURCE.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print(json.dumps(provenance,indent=2))
