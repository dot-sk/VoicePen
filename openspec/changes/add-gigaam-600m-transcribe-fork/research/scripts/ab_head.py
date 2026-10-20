import ctypes as C,hashlib,importlib.util,json,os,re,signal,subprocess,sys,time
from pathlib import Path
import numpy as np
import soundfile as sf
r=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('bench',r/'benchmark.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b);abi=b.abi
folder=r/'head-ab-f16-whole'
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def worker():
 libpath=r/'build/src/libtranscribe.dylib';lib=C.CDLL(str(libpath))
 def fn(n,a,rt=C.c_int):
  f=getattr(lib,n);f.argtypes=a;f.restype=rt;return f
 assert fn('transcribe_init_backends_default',[])()==0
 lp=abi.Load();sp=abi.Session();rp=abi.Run()
 for n,o in [('model_load',lp),('session',sp),('run',rp)]:fn('transcribe_'+n+'_params_init',[C.POINTER(type(o))],None)(C.byref(o))
 lp.backend=2;sp.n_threads=4;rp.language=b'ru';rp.timestamps=0
 model=C.c_void_p();modelpath=r/'gigaam-multilingual-large-ctc-F16.gguf';started=time.perf_counter()
 assert fn('transcribe_model_load_file',[C.c_char_p,C.POINTER(abi.Load),C.POINTER(C.c_void_p)])(str(modelpath).encode(),C.byref(lp),C.byref(model))==0
 load_s=time.perf_counter()-started;backend=fn('transcribe_model_backend',[C.c_void_p],C.c_char_p)(model).decode();assert backend=='MTL0'
 sessions={n:C.c_void_p() for n in ['cpu-head','gpu-head']}
 new=fn('transcribe_session_init',[C.c_void_p,C.POINTER(abi.Session),C.POINTER(C.c_void_p)])
 infer=fn('transcribe_run',[C.c_void_p,C.POINTER(C.c_float),C.c_int,C.POINTER(abi.Run)])
 get_text=fn('transcribe_full_text',[C.c_void_p],C.c_char_p);get_timings=fn('transcribe_get_timings',[C.c_void_p,C.POINTER(abi.Timings)]);init_timings=fn('transcribe_timings_init',[C.POINTER(abi.Timings)],None)
 for session in sessions.values():assert new(model,C.byref(sp),C.byref(session))==0
 call_index=0
 os.environ['TRANSCRIBE_GIGAAM_WHOLE_INPUT']='1';os.environ['TRANSCRIBE_GIGAAM_PROFILE_CTC']='1'
 try:
  with (folder/'runs.jsonl').open('x') as output,(folder/'calls.jsonl').open('x') as calls:
   def execute(name,a,clip,repeat,warmup):
    nonlocal call_index
    os.environ['TRANSCRIBE_GIGAAM_GPU_CTC']='1' if name=='gpu-head' else '0'
    start=time.perf_counter();status=infer(sessions[name],a.ctypes.data_as(C.POINTER(C.c_float)),len(a),C.byref(rp));elapsed=time.perf_counter()-start
    tm=abi.Timings();init_timings(C.byref(tm));assert get_timings(sessions[name],C.byref(tm))==0
    row={'sample_id':clip['sample_id'],'repeat':repeat,'config':name,'status':status,'text':(get_text(sessions[name]) or b'').decode(),'native_wall_s':elapsed,'sample_count':len(a),'audio_duration_s':len(a)/16000,'call_index':call_index,'warmup':warmup,**{k:getattr(tm,k) for k in ['mel_ms','encode_ms','decode_ms']}}
    call_index+=1;calls.write(json.dumps(row,ensure_ascii=False)+'\n');calls.flush();assert status==0,row
    return row
   for i,clip in enumerate(b.corpus['selected']):
    p=Path(clip['selected_audio_path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==clip['sha256'];audio,sr=sf.read(p,dtype='float32');assert sr==16000 and len(audio)==round(b.entries[clip['sample_id']]['duration']*16000)
    # Both paths are warmed for each exact input shape before the paired measurements.
    for name in (['cpu-head','gpu-head'] if i%2==0 else ['gpu-head','cpu-head']):execute(name,audio,clip,-1,True)
    for repeat in range(3):
     order=['cpu-head','gpu-head'] if (i+repeat)%2==0 else ['gpu-head','cpu-head']
     pair=[]
     for position,name in enumerate(order):
      row=execute(name,audio,clip,repeat,False);row['pair_order']=position;output.write(json.dumps(row,ensure_ascii=False)+'\n');output.flush();os.fsync(output.fileno());pair.append(row);print(name,clip['sample_id'],repeat,round(row['native_wall_s'],6),flush=True)
     assert pair[0]['text']==pair[1]['text'],('CPU/GPU transcript mismatch',pair)
  write(folder/'metadata.json',{'backend':backend,'threads':4,'model_load_s':load_s,'model_sha256':hashlib.sha256(modelpath.read_bytes()).hexdigest(),'library_sha256':hashlib.sha256(libpath.read_bytes()).hexdigest(),'storage':'F16 with F32 norm/bias/frontend','compute':'F32 activations','protocol':'same model, separate per-path sessions, both paths warmed on each exact input shape; 3 interleaved pairs, alternating first path by sample+repeat','calls_including_warmups':call_index,'repeats':3,'input_policy':'whole','prompt':None,'vocabulary':None,'timestamps':'none'})
 finally:
  for session in sessions.values():fn('transcribe_session_free',[C.c_void_p],None)(session)
  fn('transcribe_model_free',[C.c_void_p],None)(model)
def supervise():
 folder.mkdir(exist_ok=True);command=[sys.executable,str(Path(__file__).resolve()),'worker'];start=time.perf_counter()
 with (folder/'progress.log').open('w') as out,(folder/'native.log').open('w') as err:
  p=subprocess.Popen(command,stdout=out,stderr=err,start_new_session=True)
  try:p.wait(timeout=600)
  finally:
   if p.poll() is None:
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
   result={'command':command,'exit_code':p.returncode,'elapsed_s':time.perf_counter()-start};write(folder/'process.json',result)
 assert p.returncode==0,result
 native=(folder/'native.log').read_text();readbacks=re.findall(r'GIGAAM_CTC_READBACK gpu=(\d+) frames=(\d+) width=(\d+) bytes=(\d+) readback_us=(\d+) graph_us=(\d+)',native);decodes=re.findall(r'GIGAAM_CTC_DECODE gpu=(\d+) decode_us=(\d+)',native);calls=[json.loads(t) for t in (folder/'calls.jsonl').read_text().splitlines()];assert len(calls)==len(readbacks)==len(decodes)
 profiles=[]
 for call,readback,decode in zip(calls,readbacks,decodes):
  gpu,frames,width,nbytes,download_us,graph_us=map(int,readback);decode_gpu,decode_us=map(int,decode);assert gpu==decode_gpu==int(call['config']=='gpu-head')
  profiles.append({'call_index':call['call_index'],'config':call['config'],'sample_id':call['sample_id'],'repeat':call['repeat'],'warmup':call['warmup'],'readback_bytes':nbytes,'readback_us':download_us,'graph_us':graph_us,'decode_us':decode_us})
 write(folder/'native-profiles.json',profiles);print(json.dumps(result),flush=True)
if __name__=='__main__':
 if len(sys.argv)>1:worker()
 else:supervise()
