"""Compare all four existing v3 profiles with the pinned pre-extension native build."""
import argparse
import json
from pathlib import Path
import soundfile as sf
from prepare import ROOT,sha256
from run import run


def records(path):
    rows=[json.loads(line) for line in path.read_text().splitlines() if line.startswith('{')]
    contract=next(r for r in rows if r.get('legacy_contracts'))
    prompt=next(r for r in rows if 'legacy_prompt_status' in r)
    output=next(r for r in rows if 'repeat' in r)
    return {'contracts':contract,'legacy_prompt':prompt,'status':output['status'],'text':output['text'],'token_ids':output['token_ids'],'sample_count':output['sample_count']}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['baseline','candidate','models','speech','dataset','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    pins=json.loads((ROOT/'pins.json').read_text())
    if sha256(a.dataset)!=pins['evaluation_inputs']['dataset_sha256']:raise ValueError('private dataset identity')
    fixture=json.loads((ROOT/'fixtures/public-speech.json').read_text())
    short=next(e for e in fixture['entries'] if e['id']=='ru')
    longest=max(json.loads(a.dataset.read_text())['entries'],key=lambda e:e['duration'])
    inputs=[]
    for name,path,entry in [('short',a.speech/short['audio'],short),('longest',a.dataset.parent/longest['audio'],longest)]:
        if sha256(path)!=entry['sha256']:raise ValueError('audio digest')
        audio,sr=sf.read(path,dtype='float32')
        if sr!=16000 or audio.ndim!=1:raise ValueError('audio geometry')
        pcm=a.output/(name+'.f32');audio.tofile(pcm);inputs.append((name,pcm,len(audio)))
    reports=[]
    for entry in json.loads((ROOT/'fixtures/v3-regression.json').read_text())['entries']:
        model=a.models/entry['file']
        if sha256(model)!=entry['sha256']:raise ValueError('v3 model digest: '+entry['variant'])
        for name,pcm,count in inputs:
            folder=a.output/entry['variant']/name;folder.mkdir(parents=True)
            for kind,client in [('baseline',a.baseline),('candidate',a.candidate)]:
                run([client.resolve(),model.resolve(),pcm.resolve(),'--legacy-contracts'],folder/(kind+'.log'),120)
            baseline=records(folder/'baseline.log');candidate=records(folder/'candidate.log')
            report={'variant':entry['variant'],'fixture':name,'sample_count':count,'pass':baseline==candidate and candidate['status']==0 and candidate['sample_count']==count,'baseline':baseline,'candidate':candidate}
            (folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
            reports.append(report);print(entry['variant'],name,report['pass'],flush=True)
    result={'pass':len(reports)==8 and all(r['pass'] for r in reports),'baseline_client_sha256':sha256(a.baseline),'candidate_client_sha256':sha256(a.candidate),'fixture_manifest_sha256':sha256(ROOT/'fixtures/v3-regression.json'),'checks':[{'variant':r['variant'],'fixture':r['fixture'],'pass':r['pass']} for r in reports]}
    (a.output/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    if not result['pass']:raise SystemExit(1)
