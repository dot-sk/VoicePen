"""Validate a complete immutable corpus and score all four frozen protocols."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import statistics
import unicodedata
import jiwer
from prepare import sha256
from parity import validate_policy
ROOT=Path(__file__).resolve().parents[1]
RESEARCH=ROOT.parents[1]/'openspec/changes/add-gigaam-600m-transcribe-fork/research'


def verify_policy_digests(pins, dependency_root=RESEARCH/'dependencies'):
    for key,file in [('rescore_spellings','rescore_spellings.py'),('rescore_hesitations','rescore_hesitations.py'),('aliases','term-spelling-policy.json')]:
        if sha256(dependency_root/file)!=pins['evaluation_inputs'][key+'_sha256']:
            raise ValueError('frozen scoring policy digest mismatch: '+file)


def normalizers():
    namespace={'re':re,'unicodedata':unicodedata}
    for file,names in [(RESEARCH/'dependencies/rescore_spellings.py',{'base','normalize'}),(RESEARCH/'dependencies/rescore_hesitations.py',{'strip_hesitations'})]:
        for node in ast.parse(file.read_text()).body:
            if isinstance(node,ast.FunctionDef) and node.name in names:
                exec(compile(ast.Module(body=[node],type_ignores=[]),'frozen-scorer','exec'),namespace)
            if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id in {'dash','tokens','hesitation'} for t in node.targets):
                exec(compile(ast.Module(body=[node],type_ignores=[]),'frozen-policy','exec'),namespace)
    policy=json.loads((RESEARCH/'dependencies/term-spelling-policy.json').read_text())
    aliases={}
    base=namespace['base']
    for canonical,variants in policy['aliases'].items():
        for variant in [canonical,*variants]:
            key,value=tuple(base(variant)),tuple(base(canonical))
            if key in aliases and aliases[key]!=value: raise ValueError('ambiguous frozen aliases')
            aliases[key]=value
    namespace.update(aliases=aliases,max_length=max(map(len,aliases)))
    raw=lambda text:' '.join(base(text))
    strip=lambda text:namespace['strip_hesitations'](text)[0]
    return {'base':raw,'aliases':namespace['normalize'],'hesitation_base':lambda t:raw(strip(t)),'hesitation_aliases':lambda t:namespace['normalize'](strip(t))}


def membership(rows,ids,repeats=1):
    keys=[(r['sample_id'],r.get('repeat',0)) for r in rows]
    expected={(sid,i) for sid in ids for i in range(repeats)}
    if len(keys)!=len(set(keys)) or set(keys)!=expected: raise ValueError('incomplete, duplicate or surplus corpus membership')
    if any(r.get('status',0)!=0 for r in rows): raise ValueError('failed corpus request')


def verify_dataset(path,expected_digest=None,verify_audio=True):
    if expected_digest and sha256(path)!=expected_digest: raise ValueError('snapshot digest mismatch')
    data=json.loads(path.read_text())
    entries=data['entries']
    ids=[e['id'] for e in entries]
    if len(set(ids))!=len(ids): raise ValueError('duplicate corpus IDs')
    if verify_audio:
        import soundfile as sf
        for e in entries:
            audio=path.parent/e['audio']
            if sha256(audio)!=e['sha256']: raise ValueError('audio digest mismatch: '+e['id'])
            info=sf.info(audio)
            if info.samplerate!=16000 or info.channels!=1 or info.frames!=round(e['duration']*16000): raise ValueError('audio geometry mismatch')
    return entries


def edit_metrics(reference,hypothesis,normalizer):
    ref,hyp=normalizer(reference),normalizer(hypothesis)
    word=jiwer.process_words(ref,hyp);char=jiwer.process_characters(ref,hyp)
    def counts(result):
        return {'substitutions':result.substitutions,'deletions':result.deletions,'insertions':result.insertions,'edits':result.substitutions+result.deletions+result.insertions,'denominator':result.hits+result.substitutions+result.deletions,'alignments':[[vars(chunk) for chunk in group] for group in result.alignments]}
    return {'reference_normalized':ref,'hypothesis_normalized':hyp,'word':counts(word),'character':counts(char),'wer':word.wer,'cer':char.cer}


def evaluate(entries,candidate,oracle,baseline,candidate_identity,oracle_identity):
    validate_policy(candidate_identity['window_policy'],oracle_identity['window_policy'])
    if candidate_identity['model_sha256']==oracle_identity.get('model_sha256') and candidate_identity['role']!=oracle_identity['role']:
        raise ValueError('variant/reference identities must be separate')
    ids=[e['id'] for e in entries]
    membership(candidate,ids,3);membership(oracle,ids);membership(baseline,ids,3)
    norms=normalizers();base=norms['base']
    oracle={r['sample_id']:r for r in oracle};frozen={r['sample_id']:r for r in baseline if r['repeat']==0}
    rows=[];failures=[]
    for entry in entries:
        sid=entry['id'];calls=[r for r in candidate if r['sample_id']==sid]
        if len({r['text'] for r in calls})!=1: failures.append({'sample_id':sid,'check':'repeat output stability'})
        first=calls[0]
        for name,reference in [('matched-window oracle',oracle[sid]),('research stock25 baseline',frozen[sid])]:
            if base(first['text'])!=base(reference['text']): failures.append({'sample_id':sid,'check':name})
        rows.append({'sample_id':sid,'raw_text':first['text'],'protocols':{name:edit_metrics(entry['reference'],first['text'],norm) for name,norm in norms.items()},'calls':calls,'oracle_equal':base(first['text'])==base(oracle[sid]['text']),'baseline_equal':base(first['text'])==base(frozen[sid]['text'])})
    aggregates={}
    for protocol in norms:
        aggregates[protocol]={}
        for unit,rate in [('word','wer'),('character','cer')]:
            counts={field:sum(row['protocols'][protocol][unit][field] for row in rows) for field in ['substitutions','deletions','insertions','edits','denominator']}
            aggregates[protocol][unit]={**counts,rate:counts['edits']/counts['denominator'] if counts['denominator'] else 0.}
    return {'acceptance_scope':'full-corpus transcript and scoring gate only; not package acceptance','accepted':not failures,'failures':failures,'candidate':candidate_identity,'oracle':oracle_identity,'protocol_hashes':{file:sha256(RESEARCH/'dependencies'/file) for file in ['rescore_spellings.py','rescore_hesitations.py','term-spelling-policy.json']},'aggregate':aggregates,'recordings':rows,'timing':{'median_s':statistics.median(r['native_wall_s'] for r in candidate),'peak_rss_bytes':max(r.get('peak_rss_bytes',0) for r in candidate)}}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['dataset','candidate','oracle','baseline','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args()
    def read(folder):return [json.loads(line) for line in (folder/'runs.jsonl').read_text().splitlines()]
    pins=json.loads((ROOT/'pins.json').read_text())
    verify_policy_digests(pins)
    entries=verify_dataset(a.dataset,pins['evaluation_inputs']['dataset_sha256'])
    result=evaluate(entries,read(a.candidate),read(a.oracle),read(a.baseline),json.loads((a.candidate/'metadata.json').read_text()),json.loads((a.oracle/'metadata.json').read_text()))
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'accepted':result['accepted'],'failures':result['failures'],'aggregate':result['aggregate'],'timing':result['timing']},indent=2))
    if not result['accepted']:raise SystemExit(1)


def quantized_nonregression(candidate,accepted_f16):
    failures=[]
    native={r['sample_id']:r for r in candidate['recordings']}
    baseline={r['sample_id']:r for r in accepted_f16['recordings']}
    if set(native)!=set(baseline):raise ValueError('Q8/F16 corpus membership mismatch')
    for sid,row in native.items():
        for unit in ['word','character']:
            if row['protocols']['base'][unit]['edits']>baseline[sid]['protocols']['base'][unit]['edits']:
                failures.append({'sample_id':sid,'check':'base '+unit+' edit regression'})
    for protocol in accepted_f16['aggregate']:
        for unit,rate in [('word','wer'),('character','cer')]:
            if candidate['aggregate'][protocol][unit][rate]>accepted_f16['aggregate'][protocol][unit][rate]:
                failures.append({'protocol':protocol,'check':rate+' regression'})
    return {'accepted':not failures,'failures':failures}
