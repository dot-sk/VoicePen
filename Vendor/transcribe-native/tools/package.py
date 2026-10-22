"""Stage an isolated local XCFramework and its exact content/provenance manifest."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
from prepare import ROOT,sha256
from run import run


def files(root):
    return {str(p.relative_to(root)):sha256(p) for p in sorted(root.rglob('*')) if p.is_file() and not p.is_symlink() and p!=root/'manifest.json'}

def verify(root):
    manifest=json.loads((root/'manifest.json').read_text())
    if manifest['schema_version']!=1 or manifest['interface_version']!='0.4.0' or manifest['target']['deployment_target']!='15.0':raise ValueError('incompatible manifest/interface')
    links={str(p.relative_to(root)):str(p.readlink()) for p in sorted(root.rglob('*')) if p.is_symlink()}
    if links!=manifest.get('symlinks',{}):raise ValueError('altered package symlink')
    for path in links:
        resolved=(root/path).resolve()
        if not resolved.is_relative_to(root.resolve()) or not resolved.exists():raise ValueError('missing or escaping package resource link')
    actual=files(root)
    if actual!=manifest['files']:raise ValueError('altered checksum, missing resource or unexpected package content')
    if not manifest['licenses'] or any(name not in actual for name in manifest['licenses']):raise ValueError('incomplete license record')
    return manifest


def package(source,build,output,model):
    if output.exists():raise ValueError('output already exists')
    pins=json.loads((ROOT/'pins.json').read_text())
    output.mkdir(parents=True)
    framework=output/'VoicePenGigaAM.framework'
    shutil.copytree(build/'src/VoicePenGigaAM.framework',framework,symlinks=True)
    version=framework/'Versions/A'
    headers=version/'Headers';headers.mkdir(exist_ok=True)
    shutil.copytree(source/'include',headers,dirs_exist_ok=True)
    modules=version/'Modules';modules.mkdir(exist_ok=True)
    (modules/'module.modulemap').write_text('framework module VoicePenGigaAM {\n  header "transcribe.h"\n  export *\n}\n')
    for name in ['Headers','Modules']:
        link=framework/name
        if not link.exists():link.symlink_to('Versions/Current/'+name)
    binary=version/'VoicePenGigaAM'
    symbols=subprocess.check_output(['nm','-gjU',str(binary)],text=True).splitlines()
    unexpected=[name for name in symbols if not name.startswith('_transcribe_')]
    if unexpected:raise ValueError('private symbols exported: '+repr(unexpected[:10]))
    classes=subprocess.check_output(['otool','-ov',str(binary)],text=True)
    if 'GGMLMetalClass' in classes:raise ValueError('unexpected global Metal resource class')
    deps='\n'.join(subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:])
    if 'libggml' in deps or '/Users/' in deps:raise ValueError('private dylib or checkout dependency')
    (output/'exports.txt').write_text('\n'.join(symbols)+'\n')
    (output/'dependencies.txt').write_text(deps.replace(str(binary),'VoicePenGigaAM'))
    licenses=output/'licenses';shutil.copytree(ROOT/'licenses',licenses)
    for name,path in [('LICENSE.miniz',source/'src/third_party/miniz/LICENSE'),('LICENSE.silero_vad',source/'src/third_party/silero_vad/LICENSE')]:shutil.copyfile(path,licenses/name)
    run(['xcodebuild','-create-xcframework','-framework',framework.resolve(),'-output',(output/'VoicePenGigaAM.xcframework').resolve()],output.parent/(output.name+'-xcframework.log'),120)
    compiler_file=next((build/'CMakeFiles').glob('*/CMakeCXXCompiler.cmake'))
    compiler=compiler_file.read_text()
    compiler_version=re.search(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"',compiler).group(1)
    build_version=subprocess.check_output(['otool','-l',str(binary)],text=True).split('LC_BUILD_VERSION',1)[1]
    sdk=re.search(r'\bsdk ([0-9.]+)',build_version).group(1)
    symlinks={str(p.relative_to(output)):str(p.readlink()) for p in sorted(output.rglob('*')) if p.is_symlink()}
    manifest={'schema_version':1,'candidate':pins['candidate'],'acceptance':'unaccepted','interface_version':'0.4.0','target':pins['target'],'profile':pins['profile'],'head_decision':pins['head_decision'],'upstream':pins['upstream'],'ggml':pins['ggml'],'model':{**pins['model'],'gguf_sha256':sha256(model)},'metal_resources':'embedded, framework-owned source; no bundle/env/cwd lookup','objc_resource_classes':[],'build_inputs':{'compiler':'AppleClang '+compiler_version,'compiler_configuration_sha256':sha256(compiler_file),'sdk':sdk,'flags':{'configuration':'Release','TRANSCRIBE_ISOLATED_FRAMEWORK':True,'TRANSCRIBE_BUILD_SHARED':False,'GGML_METAL_EMBED_LIBRARY':True,'TRANSCRIBE_ENABLE_VALIDATION_HOOKS':False,'TRANSCRIBE_USE_OPENMP':False,'parallelism':2,'linker_uuid':'toolchain-generated; required for consumer linkage','signing':'unsigned local candidate'}},'source':json.loads((source/'VOICEPEN_SOURCE.json').read_text()) if (source/'VOICEPEN_SOURCE.json').exists() else {'status':'development tree, not reproducible acceptance'},'symlinks':symlinks,'licenses':[str(p.relative_to(output)) for p in licenses.iterdir() if p.is_file()],'files':files(output)}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    verify(output)
    print(json.dumps({'candidate':manifest['candidate'],'library_sha256':sha256(binary),'model_sha256':sha256(model),'exported_symbols':len(symbols),'accepted':False}))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='action',required=True)
    v=sub.add_parser('verify');v.add_argument('package',type=Path)
    b=sub.add_parser('build')
    for name in ['source','build','output','model']:b.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args()
    if a.action=='verify':verify(a.package);print('package checksums/interface/resources/licenses verified')
    else:package(a.source,a.build,a.output,a.model)
