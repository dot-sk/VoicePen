"""Clean native matrix: tools/tests diagnostics or isolated production framework."""
import argparse
from pathlib import Path
from run import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--cmake',required=True)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--build',type=Path,required=True)
    p.add_argument('--mode',choices=['tests-tools','framework'],required=True)
    a=p.parse_args()
    if a.build.exists():raise ValueError('clean build directory required')
    a.build.mkdir(parents=True)
    flags=['-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0','-DTRANSCRIBE_BUILD_EXAMPLES=OFF','-DGGML_METAL_EMBED_LIBRARY=ON','-DTRANSCRIBE_INSTALL=OFF']
    test=a.mode=='tests-tools'
    flags += ['-DTRANSCRIBE_BUILD_TESTS='+('ON' if test else 'OFF'),'-DTRANSCRIBE_BUILD_TOOLS='+('ON' if test else 'OFF'),'-DTRANSCRIBE_ENABLE_VALIDATION_HOOKS='+('ON' if test else 'OFF'),'-DTRANSCRIBE_ISOLATED_FRAMEWORK='+('OFF' if test else 'ON')]
    run([a.cmake,'-S',a.source,'-B',a.build,*flags],a.build/'configure.log',120)
    run([a.cmake,'--build',a.build,'--parallel','2'],a.build/'build.log',600)
