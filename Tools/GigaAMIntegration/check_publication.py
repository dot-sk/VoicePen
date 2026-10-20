"""Exercise the GigaAM publisher offline against prepared private assets."""
import argparse,hashlib,json,os,shutil,subprocess,tempfile,zipfile
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('assets',type=Path); args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]; assets=args.assets.resolve(); plan=json.loads((assets/'gigaam-publication-plan.json').read_text())
with zipfile.ZipFile(assets/'gigaam-600m-F16-notices.zip') as archive:
    native=json.loads((assets/'native-package-manifest.json').read_text())
    assert set(archive.namelist())==set(native['licenses'])|{'MODEL_PROVENANCE.json','MODEL_SHA256SUMS'}
    for relative in native['licenses']: assert hashlib.sha256(archive.read(relative)).hexdigest()==native['files'][relative]
with tempfile.TemporaryDirectory(prefix='gigaam-publish-check-',dir='/private/tmp') as temporary:
    root=Path(temporary); target=root/'assets'; target.mkdir(); mock=root/'bin';mock.mkdir()
    for path in assets.iterdir():
        if path.name=='gigaam-600m-F16.gguf': os.link(path,target/path.name)
        elif path.is_file(): shutil.copy2(path,target/path.name)
        elif path.is_dir(): shutil.copytree(path,target/path.name)
    (target/'gigaam-600m-F16-notices.zip').unlink()
    subprocess.run(['uv','--native-tls','run','--offline','--no-project','--python','3.13','python',str(repo/'Tools/GigaAMIntegration/prepare_publication.py'),str(target)],check=True,stdout=subprocess.DEVNULL)
    assert hashlib.sha256((target/'gigaam-600m-F16-notices.zip').read_bytes()).hexdigest()==plan['assets'][1]['sha256']
    (target/'gigaam-publication-plan.json').unlink()
    bad=dict(plan,tag='model-assets-v1');(target/'gigaam-publication-plan.json').write_text(json.dumps(bad))
    command=['bash',str(repo/'scripts/publish-model-assets.sh'),'--gigaam',str(target)]
    assert subprocess.run(command+['--dry-run'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    (target/'gigaam-publication-plan.json').write_text(json.dumps(plan))
    release=root/'release.json';release.write_text(json.dumps({'id':123,'tag_name':plan['tag'],'target_commitish':plan['targetCommit'],'draft':False,'assets':[{'name':a['name'],'size':a['byteSize']} for a in plan['assets']]}))
    calls=root/'calls'; gh=mock/'gh';gh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\ncase "$*" in "api repos/dot-sk/VoicePen/releases/tags/"*) cat "$MOCK_RELEASE";; *) exit 90;; esac\n');gh.chmod(0o755)
    curl=mock/'curl';curl.write_text('#!/bin/sh\nexit 22\n');curl.chmod(0o755)
    env=dict(os.environ,PATH=str(mock)+':'+os.environ['PATH'],MOCK_RELEASE=str(release),MOCK_CALLS=str(calls),MOCK_ASSETS=str(target))
    assert subprocess.run(command+['--publish'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==73
    assert len(calls.read_text().splitlines())==1
    original_gh=gh.read_text()
    gh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\ncase "$*" in "api --paginate --slurp "*) printf "[[]]\\n";; *) printf "HTTP 404\\n" >&2; exit 1;; esac\n')
    rejected=root/'rejected.json'; rejected.write_text(json.dumps({'schema_version':1,'model_artifact':{'accepted':False}}))
    assert subprocess.run(command+['--publish'],env=dict(env,GIGAAM_MODEL_ACCEPTANCE_REPORT=str(rejected)),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    assert len(calls.read_text().splitlines())==3
    gh.write_text(original_gh)
    assert subprocess.run(command+['--verify-only'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    assert not (target/'verified-model-manifest-entry.json').exists()
    curl.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "--output" ]; then shift; output="$1"; fi; url="$1"; shift; done\ncp -c "$MOCK_ASSETS/$(basename "$url")" "$output"\n')
    subprocess.run(command+['--verify-only'],env=env,check=True,stdout=subprocess.DEVNULL)
    entry=json.loads((target/'verified-model-manifest-entry.json').read_text()); assert entry['downloadURL']=='https://github.com/dot-sk/VoicePen/releases/download/model-assets-gigaam-600m-f16-v1/gigaam-600m-F16.gguf'
    assert json.loads((target/'publication-receipt.json').read_text())['verified'] is True
    curl.write_text('#!/bin/sh\nexit 22\n')
    assert subprocess.run(command+['--verify-only'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    assert not (target/'verified-model-manifest-entry.json').exists() and not (target/'publication-receipt.json').exists()

    draft=root/'draft.json'; draft.write_text(json.dumps(dict(json.loads(release.read_text()),draft=True)))
    state=root/'state'; state.write_text('created')
    acceptance=root/'accepted.json'; acceptance.write_text(json.dumps({
        'schema_version':1,'model_artifact':{'accepted':True,'sha256':plan['assets'][0]['sha256']},
        'runtime_sha256':'f2fe97a8a947483484d60c8af5e4179b26355387c2765cf83d62a7a83dbb3330',
        'candidate_manifest_sha256':plan['nativePackageManifestSHA256']}))
    gh.write_text('''#!/bin/sh
printf "%s\\n" "$*" >> "$MOCK_CALLS"
phase="$(cat "$MOCK_STATE")"
case "$*" in
  "api repos/dot-sk/VoicePen/releases/tags/"*)
    if [ "$phase" = published ]; then cat "$MOCK_RELEASE"; else printf 'HTTP 404\\n' >&2; exit 1; fi;;
  "api --paginate --slurp repos/dot-sk/VoicePen/releases?per_page=100")
    if [ "$phase" = none ]; then printf '[[]]\\n'; else jq -s '[.]' "$MOCK_DRAFT"; fi;;
  "api repos/dot-sk/VoicePen/git/ref/tags/"*) printf 'HTTP 404\\n' >&2; exit 1;;
  "api repos/dot-sk/VoicePen/commits/"*) jq -r .targetCommit "$MOCK_PLAN";;
  "release create "*) printf created > "$MOCK_STATE";;
  "release upload "*) printf uploaded > "$MOCK_STATE";;
  "api repos/dot-sk/VoicePen/releases/123") cat "$MOCK_DRAFT";;
  "api --method PATCH repos/dot-sk/VoicePen/releases/123 -F draft=false -f make_latest=false")
    printf published > "$MOCK_STATE"; cat "$MOCK_RELEASE";;
  *) exit 90;;
esac
''')
    draft_env=dict(env,MOCK_DRAFT=str(draft),MOCK_STATE=str(state),MOCK_PLAN=str(target/'gigaam-publication-plan.json'),GIGAAM_MODEL_ACCEPTANCE_REPORT=str(acceptance))
    calls.write_text('')
    assert subprocess.run(command+['--publish'],env=draft_env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==73
    assert state.read_text()=='created' and len(calls.read_text().splitlines())==2
    state.write_text('none')
    curl.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "--output" ]; then shift; output="$1"; fi; url="$1"; shift; done\ncp -c "$MOCK_ASSETS/$(basename "$url")" "$output"\n')
    subprocess.run(command+['--publish'],env=draft_env,check=True,stdout=subprocess.DEVNULL)
    assert state.read_text()=='published'
    assert json.loads((target/'publication-receipt.json').read_text())['verified'] is True
print('PASS: notices hashes/membership; deterministic archive; legacy tag refusal; existing published/draft release protection; unaccepted model refusal; readback failure/success and stale receipt cleanup; draft publication by ID when tag lookup returns 404. No real publication.')
