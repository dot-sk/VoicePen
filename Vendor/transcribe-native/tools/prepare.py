"""Extract a digest-pinned upstream archive and apply the maintained patch series."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]

def sha256(path):
    with Path(path).open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()

def prepare(archive, output):
    pins = json.loads((ROOT / 'pins.json').read_text())
    if sha256(archive) != pins['upstream']['archive_sha256']:
        raise ValueError('upstream archive digest mismatch')
    output.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts[1:]
            if not parts:
                continue
            member.name = str(Path(*parts))
            tar.extract(member, output, filter='data')
    patches = []
    for patch in sorted((ROOT / 'patches').glob('*.patch')):
        subprocess.run(['patch', '--batch', '-p1', '-i', str(patch)], cwd=output, check=True)
        patches.append({'path': patch.name, 'sha256': sha256(patch)})
    (output / 'VOICEPEN_SOURCE.json').write_text(json.dumps({'upstream': pins['upstream'], 'patches': patches}, indent=2)+'\n')

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    prepare(a.archive, a.output)
