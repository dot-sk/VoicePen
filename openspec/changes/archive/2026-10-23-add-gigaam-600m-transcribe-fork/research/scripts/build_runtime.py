import json, os, shutil, subprocess, time, signal
from pathlib import Path
root=Path(__file__).resolve().parent
commands=[['cmake','-S',str(root/'source'),'-B',str(root/'build'),'-DCMAKE_BUILD_TYPE=Release','-DTRANSCRIBE_BUILD_SHARED=ON','-DTRANSCRIBE_BUILD_TESTS=OFF','-DTRANSCRIBE_BUILD_EXAMPLES=ON','-DTRANSCRIBE_BUILD_TOOLS=ON','-DGGML_METAL=ON','-DGGML_METAL_EMBED_LIBRARY=ON'],['cmake','--build',str(root/'build'),'--parallel','2','--target','transcribe-cli','transcribe-bench','transcribe-quantize']]
results=[]
for i,cmd in enumerate(commands):
 started=time.monotonic()
 with (root/('configure.log' if i==0 else 'build.log')).open('w') as log:
  p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  try:p.wait(timeout=420)
  finally:
   if p.poll() is None:
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  results.append({'command':cmd,'exit_code':p.returncode,'elapsed_s':time.monotonic()-started})
  (root/'build-process.json').write_text(json.dumps(results,indent=2)+'\n')
  assert p.returncode==0,results[-1]
print(json.dumps(results))
