"""Verify clean rebuild contents, reject damaged candidates, restore the frozen candidate pair."""
import argparse
import json
from pathlib import Path
import shutil
import struct
from package import verify
from prepare import sha256


def normalized_macho(path):
    data=bytearray(path.read_bytes())
    if struct.unpack_from('<I',data)[0]!=0xfeedfacf:raise ValueError('expected arm64 Mach-O')
    count=struct.unpack_from('<I',data,16)[0];offset=32;ignored=[]
    for _ in range(count):
        command,size=struct.unpack_from('<II',data,offset)
        if command==0x1b:
            data[offset+8:offset+24]=bytes(16);ignored.append('LC_UUID')
        if command==0x1d:
            start,length=struct.unpack_from('<II',data,offset+8)
            data[start:start+length]=bytes(length);ignored.append('LC_CODE_SIGNATURE payload')
        offset+=size
    return bytes(data),ignored


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['candidate','rebuilt','model','output']:p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    original=verify(a.candidate);rebuilt=verify(a.rebuilt)
    if sha256(a.model)!=original['model']['gguf_sha256'] or original['model']!=rebuilt['model']:raise ValueError('different model pair')
    if original['source']!=rebuilt['source'] or original['profile']!=rebuilt['profile'] or original['build_inputs']!=rebuilt['build_inputs']:raise ValueError('different source/profile/toolchain inputs')
    if set(original['files'])!=set(rebuilt['files']) or original['symlinks']!=rebuilt['symlinks']:raise ValueError('different package contents')
    variations=[]
    for name,digest in original['files'].items():
        if digest==rebuilt['files'][name]:continue
        if not name.endswith('/VoicePenGigaAM'):raise ValueError('nonbinary package content differs: '+name)
        before,ignored=normalized_macho(a.candidate/name);after,_=normalized_macho(a.rebuilt/name)
        if before!=after:raise ValueError('binary differs beyond UUID/signature: '+name)
        variations.append({'file':name,'allowed_variation':ignored,'original_sha256':digest,'rebuilt_sha256':rebuilt['files'][name]})
    modified=a.output/'rejected-candidate';shutil.copytree(a.candidate,modified,symlinks=True)
    binary=modified/'VoicePenGigaAM.framework/Versions/A/VoicePenGigaAM'
    cases=[]
    def rejected(name):
        try:verify(modified)
        except ValueError as error:cases.append({'case':name,'rejected':True,'reason':str(error)})
        else:raise ValueError('bad candidate was accepted: '+name)
    payload=binary.read_bytes();binary.write_bytes(payload+b'corrupt');rejected('altered-checksum');binary.write_bytes(payload)
    binary.unlink();rejected('missing-embedded-metal-binary');shutil.copyfile(a.candidate/'VoicePenGigaAM.framework/Versions/A/VoicePenGigaAM',binary)
    manifest_path=modified/'manifest.json';manifest_path.write_text(json.dumps({**original,'interface_version':'incompatible'}));rejected('incompatible-interface')
    shutil.rmtree(modified)
    restored=a.output/'restored-candidate';shutil.copytree(a.candidate,restored,symlinks=True);verify(restored)
    if sha256(restored/'manifest.json')!=sha256(a.candidate/'manifest.json'):raise ValueError('restore changed candidate')
    result={'pass':True,'candidate_manifest_sha256':sha256(a.candidate/'manifest.json'),'rebuilt_manifest_sha256':sha256(a.rebuilt/'manifest.json'),'model_sha256':sha256(a.model),'package_file_count':len(original['files']),'binary_variations':variations,'rejected':cases,'restored_package':str(restored),'rollback_scope':'verified corpus-passing candidate pair; no previously accepted GigaAM pair exists'}
    (a.output/'report.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
