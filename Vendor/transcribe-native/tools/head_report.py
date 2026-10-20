"""Analyze saved head pairs plus separate same-build tensor probes, without rerunning the corpus."""
import argparse
import json
from pathlib import Path
import re
import statistics
import numpy as np
from head_ab import bindings
from evaluate import membership,normalizers,edit_metrics,verify_dataset,verify_policy_digests
from parity import compare,collapse
from prepare import ROOT,sha256

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['library','model','dataset','baseline','output','native-log','parity-dir']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args()
    pins=json.loads((ROOT/'pins.json').read_text());verify_policy_digests(pins)
    entries=verify_dataset(a.dataset,pins['evaluation_inputs']['dataset_sha256'])
    calls=[json.loads(line) for line in (a.output/'calls.jsonl').read_text().splitlines()]
    measured=[json.loads(line) for line in (a.output/'runs.jsonl').read_text().splitlines()]
    sessions={'cpu-head':None,'gpu-head':None}
    _,abi_hash=bindings()
    metadata_path=a.output/'metadata.json'
    if metadata_path.exists():
        metadata=json.loads(metadata_path.read_text())
        if metadata['model_sha256']!=sha256(a.model) or metadata['library_sha256']!=sha256(a.library):raise ValueError('different native pair')
        backend=metadata['backend'];load_s=metadata['model_load_s']
    else:
        backend=re.search(r'GPU name:\s+(MTL[0-9]+)',a.native_log.read_text()).group(1)
        load_s=None
    reference={r['sample_id']:r['text'] for r in map(json.loads,a.baseline.read_text().splitlines()) if r['repeat']==0}
    by={(r['sample_id'],r['repeat'],r['config']):r for r in measured}
    pairs=[]
    for entry in entries:
        for repeat in range(3):
            cpu,gpu=[by[entry['id'],repeat,name] for name in sessions]
            pairs.append({'sample_id':entry['id'],'repeat':repeat,'cpu_s':cpu['native_wall_s'],'gpu_s':gpu['native_wall_s'],'delta_s':gpu['native_wall_s']-cpu['native_wall_s']})
    protocols=normalizers();quality={};paths={}
    for name in sessions:
        rows=[r for r in measured if r['config']==name];membership(rows,[e['id'] for e in entries],3)
        quality[name]={entry['id']:{policy:edit_metrics(entry['reference'],by[entry['id'],0,name]['text'],normalizer) for policy,normalizer in protocols.items()} for entry in entries}
        paths[name]={'median_s':statistics.median(r['native_wall_s'] for r in rows),'sum_recording_medians_s':sum(statistics.median(r['native_wall_s'] for r in rows if r['sample_id']==entry['id']) for entry in entries),'max_shared_process_rss_bytes':max(r['peak_process_rss_bytes'] for r in rows)}
    arrays=[]
    for name in sessions:
        folder=a.parity_dir/name;probe=json.loads((folder/'probe.json').read_text())
        if not probe['pass'] or probe['head']!=name or probe['library_sha256']!=sha256(a.library) or probe['model_sha256']!=sha256(a.model):raise ValueError('different or failing head tensor probe')
        shape=json.loads((folder/'ctc.logits.raw.json').read_text())['shape'];arrays.append(np.fromfile(folder/'ctc.logits.raw.f32',dtype=np.float32).reshape(shape))
    tensor=compare(arrays[1],arrays[0],'logits','F16');tensor['exact_collapsed_tokens']=collapse(arrays[0].argmax(-1),70)==collapse(arrays[1].argmax(-1),70)
    deltas=np.array([statistics.median(p['gpu_s'] for p in pairs if p['sample_id']==entry['id'])-statistics.median(p['cpu_s'] for p in pairs if p['sample_id']==entry['id']) for entry in entries]);rng=np.random.default_rng(20261019)
    ci=np.quantile(np.mean(deltas[rng.integers(0,len(entries),size=(10000,len(entries)))],axis=1),[.025,.975]).tolist()
    native=a.native_log.read_text()
    readbacks=re.findall(r'GIGAAM_CTC_READBACK gpu=(\d+) frames=(\d+) width=(\d+) bytes=(\d+) readback_us=(\d+) graph_us=(\d+)',native)
    decodes=re.findall(r'GIGAAM_CTC_DECODE gpu=(\d+) decode_us=(\d+)',native)
    assert len(calls)==len(readbacks)==len(decodes),'incomplete native timing records'
    profiles=[]
    for call,readback,decode in zip(calls,readbacks,decodes):
        gpu,frames,width,nbytes,readback_us,graph_us=map(int,readback);decode_gpu,decode_us=map(int,decode)
        assert gpu==decode_gpu==int(call['config']=='gpu-head')
        profiles.append({'call_index':call['call_index'],'config':call['config'],'warmup':call['warmup'],'sample_id':call['sample_id'],'repeat':call['repeat'],'readback_bytes':nbytes,'readback_us':readback_us,'graph_us':graph_us,'decode_us':decode_us})
    (a.output/'native-profiles.json').write_text(json.dumps(profiles,indent=2)+'\n')
    for name in sessions:
        rows=[r for r in profiles if r['config']==name and not r['warmup']]
        paths[name].update({metric:statistics.median(r[source]/1000 for r in rows) for metric,source in [('median_readback_ms','readback_us'),('median_graph_ms','graph_us'),('median_decode_ms','decode_us')]})
    result={'pass':len(pairs)==81 and tensor['pass'] and tensor['exact_collapsed_tokens'] and quality['cpu-head']==quality['gpu-head'] and all(r['text']==reference[r['sample_id']] for r in measured),'purpose':'maintained validation build whole-input diagnostic; shipping F16 stock25 retains host head','model_sha256':sha256(a.model),'library_sha256':sha256(a.library),'abi_source_sha256':abi_hash,'dataset_sha256':sha256(a.dataset),'backend':backend,'model_load_s':load_s,'calls':len(calls),'matching_pairs':len(pairs),'protocol':'same model, separate sessions, per-shape warmup, 3 alternating-order pairs; no dumps in timed calls','paths':paths,'paired_deltas':pairs,'mean_recording_delta_bootstrap95_s':ci,'head_logits':tensor,'quality':quality}
    result['recovered_postprocessing']=not metadata_path.exists()
    runner=a.output/'runner-attempt.py'
    result['evidence_sha256']={name:sha256(path) for name,path in {'paired_calls':a.output/'calls.jsonl','measured_runs':a.output/'runs.jsonl','native_log':a.native_log,'runner':runner if runner.exists() else Path(__file__).with_name('head_ab.py'),'cpu_probe':a.parity_dir/'cpu-head/probe.json','gpu_probe':a.parity_dir/'gpu-head/probe.json'}.items()}
    result['aggregate']={}
    for name in sessions:
        result['aggregate'][name]={}
        for policy in protocols:
            result['aggregate'][name][policy]={}
            for unit,rate in [('word','wer'),('character','cer')]:
                counts={key:sum(row[policy][unit][key] for row in quality[name].values()) for key in ['substitutions','deletions','insertions','edits','denominator']}
                result['aggregate'][name][policy][unit]={**counts,rate:counts['edits']/counts['denominator'] if counts['denominator'] else 0.}
    result['corpus_relative_delta']=paths['gpu-head']['sum_recording_medians_s']/paths['cpu-head']['sum_recording_medians_s']-1
    result['paired_median_delta_s']=statistics.median(pair['delta_s'] for pair in pairs)
    result['timing_scope']='graph includes encoder plus GPU projection; synchronous readback includes transfer/synchronization, not isolated kernel timing; memory is shared-process peak'
    (a.output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    if not result['pass']:raise SystemExit(1)
