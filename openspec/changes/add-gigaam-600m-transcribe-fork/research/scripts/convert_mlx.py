import hashlib, importlib.util, json, sys
from pathlib import Path
import numpy as np
from safetensors.numpy import load_file
from gguf import GGMLQuantizationType, LlamaFileType
ROOT = Path(__file__).resolve().parent
SRC = ROOT.parent/'gigaam-20261019/models/fp16'
sys.path.insert(0,str(ROOT/'source/scripts'))
spec=importlib.util.spec_from_file_location('converter',ROOT/'source/scripts/convert-gigaam.py')
c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
config=json.loads((SRC/'config.json').read_text()); manifest=json.loads((SRC/'manifest.json').read_text())
for k in ['config','weights']:
 p=SRC/manifest[k]['file']; assert hashlib.sha256(p.read_bytes()).hexdigest()==manifest[k]['sha256']
sd=load_file(SRC/'model.safetensors')
w=c.gguf_writer(str(ROOT/'gigaam-multilingual-large-ctc-F16.gguf'),'gigaam')
c.add_general_identity(w,name='GigaAM Multilingual Large CTC',basename='gigaam-multilingual-large-ctc',size_label='585M',version='multilingual',file_type=LlamaFileType.MOSTLY_F16,languages=['ru','en','kk'],author='Salute Developers',organization='ai-sage',license='mit',license_name='MIT License',license_link='https://opensource.org/license/mit',repo_url='https://huggingface.co/ai-sage/GigaAM-Multilingual')
w.add_string('stt.variant','gigaam-multilingual-large-ctc')
for k in ['translate','lang_detect','streaming']: w.add_bool('stt.capability.'+k,False)
w.add_string('stt.gigaam.head_kind','ctc')
tok=c.extract_charwise_tokenizer(config['vocabulary'])
w.add_string('tokenizer.ggml.model','char')
for k,source in [('tokens','tokens'),('scores','scores'),('token_type','types')]:w.add_array('tokenizer.ggml.'+k,tok[source])
w.add_uint32('tokenizer.ggml.blank_token_id',70)
enc={'n_layers':24,'d_model':1024,'n_heads':16,'d_ff':4096,'conv_kernel':5,'subsampling_factor':4,'subs_kernel_size':5,'pos_emb_max_len':5000,'feat_in':64}
for k,v in enc.items():w.add_uint32('stt.gigaam.encoder.'+k,v)
w.add_string('stt.gigaam.encoder.self_attention_model','rotary');w.add_string('stt.gigaam.encoder.conv_norm_type','layer_norm')
for k,v in {'feat_in':1024,'num_classes':71}.items():w.add_uint32('stt.gigaam.head.'+k,v)
fe={'type':'mel','num_mels':64,'sample_rate':16000,'n_fft':320,'win_length':320,'hop_length':160,'window':'hann_periodic','normalize':'none','dither':0.,'pre_emphasis':0.,'f_min':0.,'f_max':8000.,'center':False,'mel_norm':'htk','log_clamp_min':1e-9,'log_clamp_max':1e9}
for k,v in fe.items():
 fn=w.add_bool if isinstance(v,bool) else w.add_uint32 if isinstance(v,int) else w.add_float32 if isinstance(v,float) else w.add_string
 fn('stt.frontend.'+k,v)
mapping=[('preprocessor.mel_filter','frontend.mel_filterbank'),('preprocessor.window','frontend.window')]
for src,dst in c.ENCODER_PRE_ENCODE_TABLE:
 src=src.replace('pre_encode.conv.0','pre_encode.conv1').replace('pre_encode.conv.2','pre_encode.conv2');mapping.append((src,dst))
for i in range(24):
 for src,dst in c.ENCODER_BLOCK_TABLE:mapping.append((f'encoder.layers.{i}.{src}',f'enc.blocks.{i}.{dst}'))
mapping.extend([('head.decoder.weight','head.ctc.weight'),('head.decoder.bias','head.ctc.bias')])
assert {s for s,d in mapping}==set(sd), sorted(set(sd)-{s for s,d in mapping})
transposes=[]; catalog=[]
for src,dst in mapping:
 a=sd[src]
 if src=='preprocessor.mel_filter':a=a.T
 elif a.ndim==3:a=a.transpose(0,2,1);transposes.append(src)
 dtype=np.float16 if a.ndim>=2 and not src.startswith('preprocessor.') else np.float32
 a=np.ascontiguousarray(a,dtype=dtype)
 w.add_tensor(dst,a,raw_dtype=GGMLQuantizationType.F16 if dtype==np.float16 else GGMLQuantizationType.F32)
 catalog.append({'source':src,'destination':dst,'shape':list(a.shape),'dtype':str(a.dtype)})
assert len(transposes)==75
w.write_header_to_file();w.write_kv_data_to_file();w.write_tensors_to_file();w.close()
output=ROOT/'gigaam-multilingual-large-ctc-F16.gguf'
(ROOT/'conversion.json').write_text(json.dumps({'source_manifest':manifest,'tensor_count':len(catalog),'conv1d_transposes':transposes,'tensors':catalog,'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'output_bytes':output.stat().st_size},indent=2)+'\n')
print('converted',output,output.stat().st_size,flush=True)
