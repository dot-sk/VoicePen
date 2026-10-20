"""Reuse complete native Q8 research outputs, enforce current frozen quality gates, report unavailability."""
import argparse
import json
from pathlib import Path
import statistics
from evaluate import edit_metrics,membership,normalizers,quantized_nonregression,verify_dataset,verify_policy_digests
from prepare import ROOT,sha256

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['research','dataset','f16','loader-log','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();pins=json.loads((ROOT/'pins.json').read_text());verify_policy_digests(pins)
    entries=verify_dataset(a.dataset,pins['evaluation_inputs']['dataset_sha256'])
    metadata=json.loads((a.research/'q8-stock25/metadata.json').read_text())
    conversion=json.loads((a.research/'quantize-process.json').read_text())
    model=a.research/'gigaam-multilingual-large-ctc-Q8_0.gguf'
    if sha256(model)!=conversion['sha256'] or conversion['sha256']!=metadata['model_sha256']:raise ValueError('different Q8 research artifact')
    if metadata['window_seconds']!=25 or metadata['context_each_side_seconds']!=2:raise ValueError('different Q8 context')
    rows=[json.loads(line) for line in (a.research/'q8-stock25/runs.jsonl').read_text().splitlines()]
    membership(rows,[entry['id'] for entry in entries],3)
    norms=normalizers();records=[]
    for entry in entries:
        calls=[r for r in rows if r['sample_id']==entry['id']]
        if len({r['text'] for r in calls})!=1:raise ValueError('unstable Q8 repeats')
        records.append({'sample_id':entry['id'],'raw_text':calls[0]['text'],'protocols':{name:edit_metrics(entry['reference'],calls[0]['text'],normalize) for name,normalize in norms.items()}})
    aggregate={}
    for name in norms:
        aggregate[name]={}
        for unit,rate in [('word','wer'),('character','cer')]:
            counts={key:sum(row['protocols'][name][unit][key] for row in records) for key in ['substitutions','deletions','insertions','edits','denominator']}
            aggregate[name][unit]={**counts,rate:counts['edits']/counts['denominator'] if counts['denominator'] else 0.}
    candidate={'recordings':records,'aggregate':aggregate}
    comparison=quantized_nonregression(candidate,json.loads(a.f16.read_text()))
    loader=a.loader_log.read_text()
    if '"load_rejection_pass":true' not in loader:raise ValueError('missing maintained-loader rejection evidence')
    result={'accepted':False,'available':False,'investigation_completed':True,'scope':'preserved native Q8 stock25 corpus, freshly scored against final F16; no maintained Q8 model has been accepted or run','reason':'research artifact lacks versioned profile/integrity metadata and is rejected by final loader; native research also misses quality non-regression','maintained_loader_log_sha256':sha256(a.loader_log),'research_model_sha256':conversion['sha256'],'research_library_sha256':metadata['library_sha256'],'dataset_sha256':sha256(a.dataset),'f16_report_sha256':sha256(a.f16),'quality_gate':comparison,'aggregate':aggregate,'recordings':records,'median_native_research_inference_s':statistics.median(row['native_wall_s'] for row in rows),'quantization_command':conversion['command']}
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'accepted':False,'available':False,'recordings':len(records),'quality_gate':comparison,'aggregate':aggregate},indent=2))
