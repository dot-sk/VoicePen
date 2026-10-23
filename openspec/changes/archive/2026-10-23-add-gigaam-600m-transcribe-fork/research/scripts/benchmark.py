import ctypes as C, hashlib, importlib.util, json, os, signal, subprocess, sys, time
from pathlib import Path
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('abi',ROOT.parent/'transcribe-cpp-20261019/benchmark.py');abi=importlib.util.module_from_spec(spec);spec.loader.exec_module(abi)
corpus=abi.CORPUS; entries=abi.ENTRIES

def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def worker(name):
 lib=C.CDLL(str(ROOT/'build/src/libtranscribe.dylib'))
 def fn(n,a,r=C.c_int):
  f=getattr(lib,n);f.argtypes=a;f.restype=r;return f
 init=fn('transcribe_init_backends_default',[]); assert init()==0
 model,session=C.c_void_p(),C.c_void_p();lp,sp,rp=abi.Load(),abi.Session(),abi.Run()
 for n,obj in [('model_load',lp),('session',sp),('run',rp)]:fn('transcribe_'+n+'_params_init',[C.POINTER(type(obj))],None)(C.byref(obj))
 lp.backend=2;sp.n_threads=4;rp.language=b'ru';rp.timestamps=0
 path=ROOT/('gigaam-multilingual-large-ctc-'+('Q8_0' if 'q8' in name else 'F16')+'.gguf')
 load=fn('transcribe_model_load_file',[C.c_char_p,C.POINTER(abi.Load),C.POINTER(C.c_void_p)])
 start=time.perf_counter();status=load(str(path).encode(),C.byref(lp),C.byref(model));assert status==0,('load',status);load_s=time.perf_counter()-start
 free_session=fn('transcribe_session_free',[C.c_void_p],None);free_model=fn('transcribe_model_free',[C.c_void_p],None)
 try:
  assert fn('transcribe_session_init',[C.c_void_p,C.POINTER(abi.Session),C.POINTER(C.c_void_p)])(model,C.byref(sp),C.byref(session))==0
  backend=fn('transcribe_model_backend',[C.c_void_p],C.c_char_p)(model).decode();assert backend=='MTL0',backend
  infer=fn('transcribe_run',[C.c_void_p,C.POINTER(C.c_float),C.c_int,C.POINTER(abi.Run)])
  get_text=fn('transcribe_full_text',[C.c_void_p],C.c_char_p)
  def execute(samples):
   t=time.perf_counter();status=infer(session,samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples),C.byref(rp));wall=time.perf_counter()-t
   tm=abi.Timings();fn('transcribe_timings_init',[C.POINTER(abi.Timings)],None)(C.byref(tm));assert fn('transcribe_get_timings',[C.c_void_p,C.POINTER(abi.Timings)])(session,C.byref(tm))==0
   return {'status':status,'text':(get_text(session) or b'').decode(),'native_wall_s':wall,**{x:getattr(tm,x) for x in ['mel_ms','encode_ms','decode_ms']}}
  folder=ROOT/name;folder.mkdir(exist_ok=True)
  selected=[c for c in corpus['selected'] if entries[c['sample_id']]['duration']<=25] if name.startswith('smoke-') else corpus['selected']
  if name.startswith('smoke-'):selected=selected[:1]
  for c in corpus['selected']:
   p=Path(c['selected_audio_path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==c['sha256']==entries[c['sample_id']]['sha256']
   info=sf.info(p);assert info.frames==round(entries[c['sample_id']]['duration']*16000) and info.samplerate==16000 and info.channels==1
  first,sr=sf.read(selected[0]['selected_audio_path'],dtype='float32');assert sr==16000
  warmup=execute(first);assert warmup['status']==0,warmup
  write(folder/'metadata.json',{'model':str(path),'model_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'engine_commit':'1dc22facfc931e2f8adb43924b0e38b9c46f83c7','backend':backend,'threads':4,'model_load_s':load_s,'warmup':warmup,'warmup_sample':selected[0]['sample_id'],'repeats':1 if name.startswith('smoke-') else 3,'timestamps':'none','prompt':None,'vocabulary':None,'window_seconds':120 if 'whole' in name else 25,'context_each_side_seconds':0 if 'whole' in name else 2})
  with (folder/'runs.jsonl').open('x') as out:
   for clip in selected:
    samples,sr=sf.read(clip['selected_audio_path'],dtype='float32');assert np.isfinite(samples).all()
    for repeat in range(1 if name.startswith('smoke-') else 3):
     row={**execute(samples),'sample_id':clip['sample_id'],'repeat':repeat,'sample_count':len(samples),'audio_duration_s':len(samples)/sr}
     out.write(json.dumps(row,ensure_ascii=False)+'\n');out.flush();os.fsync(out.fileno());print(name,clip['sample_id'],repeat,row['status'],round(row['native_wall_s'],4),flush=True);assert row['status']==0,row
 finally:free_session(session);free_model(model)
def supervise(name):
 folder=ROOT/name;folder.mkdir(exist_ok=True);env=os.environ.copy()
 if 'whole' in name:env['TRANSCRIBE_GIGAAM_WHOLE_INPUT']='1'
 if 'gpu' in name:
  env['TRANSCRIBE_GIGAAM_WHOLE_INPUT']='1'
  env['TRANSCRIBE_GIGAAM_GPU_CTC']='1'
 if name.startswith('smoke-'):
  dump=folder/'dump';dump.mkdir(exist_ok=True);env['TRANSCRIBE_DUMP_DIR']=str(dump)
 command=[sys.executable,str(Path(__file__).resolve()),'worker',name];start=time.perf_counter()
 with (folder/'progress.log').open('w') as out,(folder/'native.log').open('w') as err:
  p=subprocess.Popen(command,stdout=out,stderr=err,start_new_session=True,env=env)
  try:p.wait(timeout=600)
  finally:
   if p.poll() is None:
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
   result={'command':command,'exit_code':p.returncode,'elapsed_s':time.perf_counter()-start};write(folder/'process.json',result)
 print(json.dumps(result),flush=True);assert p.returncode==0,result
if __name__=='__main__':
 if sys.argv[1]=='worker':worker(sys.argv[2])
 else:supervise(sys.argv[1])
