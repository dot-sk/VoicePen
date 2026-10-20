"""Promoted research head A/B: exact maintained diagnostic build, unchanged paired protocol."""
import argparse
import ast
import ctypes as C
import json
import os
from pathlib import Path
import re
import resource
import statistics
import time
import numpy as np
import soundfile as sf
from evaluate import RESEARCH,edit_metrics,membership,normalizers,verify_dataset,verify_policy_digests
from parity import compare,collapse
from prepare import ROOT,sha256


def bindings():
    source=RESEARCH/'dependencies/transcribe-cpp-benchmark.py'
    scope={'C':C}
    nodes=[node for node in ast.parse(source.read_text()).body if isinstance(node,ast.ClassDef) and node.name in {'Load','Session','Ext','Run','Timings'}]
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(source),'exec'),scope)
    return scope,sha256(source)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['library','model','dataset','baseline','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--native-log',type=Path,required=True,help='stdout/stderr log opened by tools/run.py')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    pins=json.loads((ROOT/'pins.json').read_text());verify_policy_digests(pins)
    entries=verify_dataset(a.dataset,pins['evaluation_inputs']['dataset_sha256'])
    abi,abi_hash=bindings();lib=C.CDLL(str(a.library.resolve()))
    def fn(name,args,result=C.c_int):
        f=getattr(lib,'transcribe_'+name);f.argtypes=args;f.restype=result;return f
    assert fn('init_backends_default',[])()==0
    lp,sp,rp=abi['Load'](),abi['Session'](),abi['Run']()
    for name,value in [('model_load',lp),('session',sp),('run',rp)]:fn(name+'_params_init',[C.POINTER(type(value))],None)(C.byref(value))
    for value in [lp,sp,rp]:assert value.struct_size==C.sizeof(value)
    lp.backend=2;sp.n_threads=4;rp.timestamps=0
    model=C.c_void_p();started=time.perf_counter()
    assert fn('model_load_file',[C.c_char_p,C.POINTER(type(lp)),C.POINTER(C.c_void_p)])(str(a.model.resolve()).encode(),C.byref(lp),C.byref(model))==0
    load_s=time.perf_counter()-started
    backend=fn('model_backend',[C.c_void_p],C.c_char_p)(model).decode();assert backend.startswith('MTL')
    sessions={name:C.c_void_p() for name in ['cpu-head','gpu-head']}
    infer=fn('run',[C.c_void_p,C.POINTER(C.c_float),C.c_int,C.POINTER(type(rp))])
    get_text=fn('full_text',[C.c_void_p],C.c_char_p)
    calls=[];measured=[]
    os.environ['TRANSCRIBE_GIGAAM_WHOLE_INPUT']='1';os.environ['TRANSCRIBE_GIGAAM_PROFILE_CTC']='1'
    os.environ.pop('TRANSCRIBE_DUMP_DIR',None);os.environ.pop('TRANSCRIBE_DUMP_ALL_BLOCKS',None)
    try:
        for session in sessions.values():assert fn('session_init',[C.c_void_p,C.POINTER(type(sp)),C.POINTER(C.c_void_p)])(model,C.byref(sp),C.byref(session))==0
        with (a.output/'calls.jsonl').open('x') as call_file,(a.output/'runs.jsonl').open('x') as run_file:
            def execute(name,audio,sid,repeat,warmup,order=0):
                os.environ['TRANSCRIBE_GIGAAM_GPU_CTC']='1' if name=='gpu-head' else '0'
                start=time.perf_counter();status=infer(sessions[name],audio.ctypes.data_as(C.POINTER(C.c_float)),len(audio),C.byref(rp));wall=time.perf_counter()-start
                tm=abi['Timings']();fn('timings_init',[C.POINTER(type(tm))],None)(C.byref(tm));assert fn('get_timings',[C.c_void_p,C.POINTER(type(tm))])(sessions[name],C.byref(tm))==0
                row={'sample_id':sid,'repeat':repeat,'config':name,'pair_order':order,'warmup':warmup,'call_index':len(calls),'status':status,'text':(get_text(sessions[name]) or b'').decode(),'sample_count':len(audio),'native_wall_s':wall,'peak_process_rss_bytes':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,**{key:getattr(tm,key) for key in ['mel_ms','encode_ms','decode_ms']}}
                assert status==0,row
                calls.append(row);call_file.write(json.dumps(row,ensure_ascii=False)+'\n');call_file.flush()
                if not warmup:measured.append(row);run_file.write(json.dumps(row,ensure_ascii=False)+'\n');run_file.flush()
                return row
            for i,entry in enumerate(entries):
                audio,sr=sf.read(a.dataset.parent/entry['audio'],dtype='float32');assert sr==16000 and np.isfinite(audio).all()
                for name in (['cpu-head','gpu-head'] if i%2==0 else ['gpu-head','cpu-head']):execute(name,audio,entry['id'],-1,True)
                for repeat in range(3):
                    order=['cpu-head','gpu-head'] if (i+repeat)%2==0 else ['gpu-head','cpu-head']
                    pair=[execute(name,audio,entry['id'],repeat,False,position) for position,name in enumerate(order)]
                    assert pair[0]['text']==pair[1]['text'],'head transcript mismatch'
                print(entry['id'],'paired',flush=True)
    finally:
        for session in sessions.values():
            if session.value:fn('session_free',[C.c_void_p],None)(session)
        fn('model_free',[C.c_void_p],None)(model)
    metadata={'model_sha256':sha256(a.model),'library_sha256':sha256(a.library),'abi_source_sha256':abi_hash,'dataset_sha256':sha256(a.dataset),'backend':backend,'model_load_s':load_s,'calls':len(calls),'purpose':'complete paired calls, analyze separately with head_report.py'}
    (a.output/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
