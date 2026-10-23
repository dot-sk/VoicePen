import json,os,signal,subprocess,time,hashlib
from pathlib import Path
r=Path(__file__).resolve().parent
command=[str(r/'build/bin/transcribe-quantize'),str(r/'gigaam-multilingual-large-ctc-F16.gguf'),str(r/'gigaam-multilingual-large-ctc-Q8_0.gguf'),'--quant','Q8_0']
with (r/'quantize.log').open('w') as log:
 start=time.perf_counter();p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try:p.wait(timeout=120)
 finally:
  if p.poll() is None:
   os.killpg(p.pid,signal.SIGTERM)
   try:p.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  result={'command':command,'exit_code':p.returncode,'elapsed_s':time.perf_counter()-start};(r/'quantize-process.json').write_text(json.dumps(result,indent=2)+'\n')
 assert p.returncode==0,result
 output=r/'gigaam-multilingual-large-ctc-Q8_0.gguf';result.update(sha256=hashlib.sha256(output.read_bytes()).hexdigest(),bytes=output.stat().st_size);(r/'quantize-process.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
