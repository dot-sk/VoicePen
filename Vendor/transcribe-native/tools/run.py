"""Run one bounded child process, preserving its exit code and cleaning only its group."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def run(command,log,timeout=600,env=None,cwd=None):
    log=Path(log);log.parent.mkdir(parents=True,exist_ok=True)
    started=time.monotonic()
    with log.open('w') as out:
        p=subprocess.Popen([str(x) for x in command],stdout=out,stderr=subprocess.STDOUT,start_new_session=True,env=env,cwd=cwd)
        previous_handler=signal.getsignal(signal.SIGTERM)
        def interrupted(signum,frame):
            signal.signal(signal.SIGTERM,signal.SIG_IGN)
            raise SystemExit(128+signum)
        signal.signal(signal.SIGTERM,interrupted)
        try:
            p.wait(timeout=timeout)
        finally:
            if p.poll() is None:
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid,signal.SIGKILL);p.wait()
                deadline=time.monotonic()+2
                while True:
                    try:os.killpg(p.pid,0)
                    except ProcessLookupError:break
                    if time.monotonic()>=deadline:
                        os.killpg(p.pid,signal.SIGKILL);break
                    time.sleep(.01)
            record={'command':[str(x) for x in command],'exit_code':p.returncode,'elapsed_s':time.monotonic()-started}
            log.with_suffix('.process.json').write_text(json.dumps(record,indent=2)+'\n')
            signal.signal(signal.SIGTERM,previous_handler)
    if p.returncode: raise subprocess.CalledProcessError(p.returncode,command)
    return record

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=600)
    parser.add_argument('command',nargs=argparse.REMAINDER)
    args=parser.parse_args()
    command=args.command[1:] if args.command[0]=='--' else args.command
    print(json.dumps(run(command,args.log,args.timeout)))
