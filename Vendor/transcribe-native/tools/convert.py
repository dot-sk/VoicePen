"""Promoted 824-tensor research mapping, with strict pinned inputs and atomic GGUF output."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import zlib
import numpy as np
from prepare import sha256

ROOT=Path(__file__).resolve().parents[1]

def validate_config(config):
    expected=json.loads((ROOT/'model-config.json').read_text())
    if config!=expected: raise ValueError('unsupported checkpoint configuration or vocabulary')

def transform_tensor(name,array):
    if name=='preprocessor.mel_filter': return array.T
    if array.ndim==3: return array.transpose(0,2,1)
    return array

def inverse_transform(name,array):
    return transform_tensor(name,array)

def tensor_crc32(array):
    return zlib.crc32(np.ascontiguousarray(array).view(np.uint8)) & 0xffffffff


def validate_catalog(tensors,schema):
    expected={entry['source'] for entry in schema}
    if set(tensors)!=expected: raise ValueError('missing or surplus tensors')
    for entry in schema:
        a=transform_tensor(entry['source'],tensors[entry['source']])
        if list(a.shape)!=entry['shape'] or not np.isfinite(a).all():
            raise ValueError('corrupt tensor: '+entry['source'])

def convert(source,upstream,output,storage):
    from safetensors.numpy import load_file
    from gguf import GGMLQuantizationType,LlamaFileType,GGUFValueType
    pins=json.loads((ROOT/'pins.json').read_text())
    config=json.loads((source/'config.json').read_text())
    manifest=json.loads((source/'manifest.json').read_text())
    validate_config(config)
    for key,file in [('weights','model.safetensors'),('config','config.json')]:
        actual=sha256(source/file)
        if actual!=pins['model'][key+'_sha256'] or actual!=manifest[key]['sha256']:
            raise ValueError(key+' digest mismatch')
    if manifest['source']['revision']!=pins['model']['source_revision']:
        raise ValueError('source revision mismatch')
    sd=load_file(source/'model.safetensors')
    schema=json.loads((ROOT/'tensor-schema.json').read_text())
    validate_catalog(sd,schema['tensors'])
    sys.path.insert(0,str(upstream/'scripts'))
    spec=importlib.util.spec_from_file_location('converter',upstream/'scripts/convert-gigaam.py')
    c=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(c)
    temporary=output.with_suffix('.partial')
    if output.exists() or temporary.exists(): raise ValueError('output already exists')
    output.parent.mkdir(parents=True,exist_ok=True)
    w=c.gguf_writer(str(temporary),'gigaam')
    c.add_general_identity(w,name='GigaAM Multilingual Large CTC',basename='gigaam-multilingual-large-ctc',size_label='585M',version='multilingual',file_type=LlamaFileType.MOSTLY_F16 if storage=='F16' else LlamaFileType.ALL_F32,languages=pins['model']['languages'],author='Salute Developers',organization='ai-sage',license='mit',license_name='MIT License',license_link='https://opensource.org/license/mit',repo_url='https://huggingface.co/ai-sage/GigaAM-Multilingual')
    w.add_string('stt.variant',pins['profile']['id'])
    w.add_uint32('stt.gigaam.profile_version',1)
    w.add_string('stt.gigaam.window_policy','stock25-v1')
    w.add_string('stt.gigaam.source_revision',pins['model']['source_revision'])
    w.add_string('stt.gigaam.source_weights_sha256',pins['model']['weights_sha256'])
    w.add_string('stt.gigaam.storage',storage)
    for k in ['translate','lang_detect','streaming']: w.add_bool('stt.capability.'+k,False)
    w.add_string('stt.gigaam.head_kind','ctc')
    tok=c.extract_charwise_tokenizer(config['vocabulary'])
    w.add_string('tokenizer.ggml.model','char')
    for key,source_key in [('tokens','tokens'),('scores','scores'),('token_type','types')]: w.add_array('tokenizer.ggml.'+key,tok[source_key])
    w.add_uint32('tokenizer.ggml.blank_token_id',70)
    enc={'n_layers':24,'d_model':1024,'n_heads':16,'d_ff':4096,'conv_kernel':5,'subsampling_factor':4,'subs_kernel_size':5,'pos_emb_max_len':5000,'feat_in':64}
    for k,v in enc.items(): w.add_uint32('stt.gigaam.encoder.'+k,v)
    w.add_string('stt.gigaam.encoder.self_attention_model','rotary')
    w.add_string('stt.gigaam.encoder.conv_norm_type','layer_norm')
    for k,v in {'feat_in':1024,'num_classes':71}.items(): w.add_uint32('stt.gigaam.head.'+k,v)
    frontend={'type':'mel','num_mels':64,'sample_rate':16000,'n_fft':320,'win_length':320,'hop_length':160,'window':'hann_periodic','normalize':'none','dither':0.,'pre_emphasis':0.,'f_min':0.,'f_max':8000.,'center':False,'mel_norm':'htk','log_clamp_min':1e-9,'log_clamp_max':1e9}
    for k,v in frontend.items():
        fn=w.add_bool if isinstance(v,bool) else w.add_uint32 if isinstance(v,int) else w.add_float32 if isinstance(v,float) else w.add_string
        fn('stt.frontend.'+k,v)
    catalog=[]
    checksums=[]
    transposes=[]
    try:
        for entry in schema['tensors']:
            name=entry['source']
            original=sd[name]
            transformed=transform_tensor(name,original)
            if not np.array_equal(inverse_transform(name,transformed),original): raise ValueError('inverse layout failed: '+name)
            if original.ndim==3: transposes.append(name)
            dtype=np.float16 if storage=='F16' and original.ndim>=2 and not name.startswith('preprocessor.') else np.float32
            array=np.ascontiguousarray(transformed,dtype=dtype)
            if not np.array_equal(array.astype(original.dtype),transformed): raise ValueError('logical tensor values changed: '+name)
            w.add_tensor(entry['destination'],array,raw_dtype=GGMLQuantizationType.F16 if dtype==np.float16 else GGMLQuantizationType.F32)
            checksums.append(tensor_crc32(array))
            catalog.append({**entry,'dtype':str(array.dtype),'crc32':checksums[-1]})
        if len(catalog)!=824 or len(transposes)!=75: raise ValueError('tensor/transform accounting mismatch')
        w.add_key_value('stt.gigaam.tensor_crc32',checksums,GGUFValueType.ARRAY,sub_type=GGUFValueType.UINT32)
        w.write_header_to_file();w.write_kv_data_to_file();w.write_tensors_to_file();w.close()
        temporary.rename(output)
    except BaseException:
        w.close()
        temporary.unlink(missing_ok=True)
        raise
    report={'schema_version':1,'source_manifest':manifest,'converter_sha256':sha256(__file__),'schema_sha256':sha256(ROOT/'tensor-schema.json'),'tensor_count':len(catalog),'conv1d_transposes':transposes,'tensors':catalog,'storage':storage,'activations':'F32','profile':pins['profile'],'output_sha256':sha256(output),'output_bytes':output.stat().st_size}
    output.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['tensor_count','storage','output_sha256','output_bytes']}))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--upstream',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--storage',choices=['F16','F32'],default='F16')
    a=p.parse_args();convert(a.source,a.upstream,a.output,a.storage)
