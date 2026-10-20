"""Untimed same-build head tensor probe; set the process-cached dump directory before initialization."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import soundfile as sf
from evaluate import verify_dataset
from head_ab import bindings
from prepare import ROOT,sha256

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['library','model','dataset','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--head',choices=['cpu-head','gpu-head'],required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    pins=json.loads((ROOT/'pins.json').read_text());entries=verify_dataset(a.dataset,pins['evaluation_inputs']['dataset_sha256'])
    entry=next(e for e in entries if e['id']=='sample-022');audio,sr=sf.read(a.dataset.parent/entry['audio'],dtype='float32');assert sr==16000
    os.environ.update(TRANSCRIBE_GIGAAM_WHOLE_INPUT='1',TRANSCRIBE_GIGAAM_PROFILE_CTC='1',TRANSCRIBE_GIGAAM_GPU_CTC='1' if a.head=='gpu-head' else '0',TRANSCRIBE_DUMP_DIR=str(a.output.resolve()))
    os.environ.pop('TRANSCRIBE_DUMP_ALL_BLOCKS',None)
    abi,_=bindings();lib=C.CDLL(str(a.library.resolve()))
    def fn(name,args,result=C.c_int):
        f=getattr(lib,'transcribe_'+name);f.argtypes=args;f.restype=result;return f
    assert fn('init_backends_default',[])()==0
    lp,sp,rp=abi['Load'](),abi['Session'](),abi['Run']()
    for name,value in [('model_load',lp),('session',sp),('run',rp)]:fn(name+'_params_init',[C.POINTER(type(value))],None)(C.byref(value));assert value.struct_size==C.sizeof(value)
    lp.backend=2;sp.n_threads=4;rp.timestamps=0;model=C.c_void_p();session=C.c_void_p()
    try:
        assert fn('model_load_file',[C.c_char_p,C.POINTER(type(lp)),C.POINTER(C.c_void_p)])(str(a.model.resolve()).encode(),C.byref(lp),C.byref(model))==0
        assert fn('session_init',[C.c_void_p,C.POINTER(type(sp)),C.POINTER(C.c_void_p)])(model,C.byref(sp),C.byref(session))==0
        status=fn('run',[C.c_void_p,C.POINTER(C.c_float),C.c_int,C.POINTER(type(rp))])(session,audio.ctypes.data_as(C.POINTER(C.c_float)),len(audio),C.byref(rp))
        text=(fn('full_text',[C.c_void_p],C.c_char_p)(session) or b'').decode()
        backend=fn('model_backend',[C.c_void_p],C.c_char_p)(model).decode()
        result={'pass':status==0 and backend.startswith('MTL') and (a.output/'ctc.logits.raw.json').exists(),'head':a.head,'sample_id':entry['id'],'sample_count':len(audio),'model_sha256':sha256(a.model),'library_sha256':sha256(a.library),'backend':backend,'text':text,'role':'untimed whole-input head parity probe'}
        (a.output/'probe.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        if not result['pass']:raise SystemExit(1)
    finally:
        if session.value:fn('session_free',[C.c_void_p],None)(session)
        if model.value:fn('model_free',[C.c_void_p],None)(model)
