import json, os, signal, subprocess, sys, time
from pathlib import Path
r=Path(__file__).resolve().parent
name=sys.argv[1] if len(sys.argv)>1 else 'reference'
assert name in {'reference','reference_f32'}
with (r/(name+'.log')).open('w') as log:
 start=time.perf_counter();p=subprocess.Popen([sys.executable,str(r/(name+'.py'))],stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try:p.wait(timeout=600)
 finally:
  if p.poll() is None:
   os.killpg(p.pid,signal.SIGTERM)
   try:p.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  result={'exit_code':p.returncode,'elapsed_s':time.perf_counter()-start};(r/(name+'-process.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(result,flush=True);assert p.returncode==0
