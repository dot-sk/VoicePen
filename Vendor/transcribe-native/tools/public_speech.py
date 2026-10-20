"""Prepare five licensed public speech decode fixtures; audio stays outside Git."""
import argparse
import json
import hashlib
from pathlib import Path
import subprocess
import soundfile as sf
from prepare import sha256

CONFIGS={'ru':'ru_ru','en':'en_us','kk':'kk_kz','ky':'ky_kg','uz':'uz_uz'}
DATASET_REVISION='70bb2e84b976b7e960aa89f1c648e09c59f894dd'


def fetch(url,path):
    subprocess.run(['curl','--fail','--silent','--show-error','--location','--max-time','60',url,'-o',str(path)],check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--resume',action='store_true')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=a.resume)
    revision=a.output/'dataset-revision.json'
    fetch('https://huggingface.co/api/datasets/google/fleurs/revision/'+DATASET_REVISION,revision)
    info=json.loads(revision.read_text())
    if info['sha']!=DATASET_REVISION or info['cardData']['license']!=['cc-by-4.0']:raise ValueError('dataset provenance changed')
    entries=[]
    for language,config in CONFIGS.items():
        if language=='kk':
            endpoint='https://commons.wikimedia.org/w/api.php?action=query&format=json&titles=File%3AKk-0-n%C3%B6l.ogg&prop=imageinfo&iiprop=url%7Csha1%7Cextmetadata'
            response=a.output/'kk-source.json';fetch(endpoint,response)
            image=next(iter(json.loads(response.read_text())['query']['pages'].values()))['imageinfo'][0]
            if image['sha1']!='56df543508f40df93704151664d28e79dac77101' or image['extmetadata']['LicenseShortName']['value']!='CC0':raise ValueError('Kazakh source identity/license changed')
            encoded=a.output/'kk-source.audio';fetch(image['url'],encoded)
            if hashlib.sha1(encoded.read_bytes()).hexdigest()!=image['sha1']:raise ValueError('Kazakh source digest mismatch')
            audio=a.output/'kk.wav'
            subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-nostdin','-y','-i',str(encoded),'-ar','16000','-ac','1','-c:a','pcm_f32le',str(audio)],check=True)
            samples,sr=sf.read(audio,dtype='float32')
            entries.append({'id':'kk','language':'kk','audio':audio.name,'sha256':sha256(audio),'duration':len(samples)/16000,'reference':'','source':'Wikimedia Commons File:Kk-0-nöl.ogg','source_endpoint':endpoint,'source_audio_sha256':sha256(encoded),'license':'CC0-1.0','attribution':'Esetok','source_sha1':image['sha1'],'conversion':'ffmpeg 16k mono Float32 WAV, source speech resampled only for this parity fixture','role':'human pronunciation token-decoding parity fixture, no broad accuracy claim'})
            print(language,len(samples),'samples',flush=True)
            continue
        endpoint='https://datasets-server.huggingface.co/rows?dataset=google%2Ffleurs&config='+config+'&split=validation&offset=0&length=1&revision='+DATASET_REVISION
        response=a.output/(language+'-source.json');fetch(endpoint,response)
        row=json.loads(response.read_text())['rows'][0]['row']
        encoded=a.output/(language+'-source.audio');fetch(row['audio'][0]['src'],encoded)
        samples,sr=sf.read(encoded,dtype='float32')
        if sr!=16000 or samples.ndim!=1 or len(samples)!=row['num_samples']:raise ValueError('unexpected public audio geometry')
        audio=a.output/(language+'.wav');sf.write(audio,samples,16000,subtype='FLOAT')
        entries.append({'id':language,'language':language,'audio':audio.name,'sha256':sha256(audio),'duration':len(samples)/16000,'reference':'','dataset_config':config,'source_row_id':row['id'],'source_endpoint':endpoint,'source_response_sha256':sha256(response),'source_audio_sha256':sha256(encoded),'license':'CC-BY-4.0','attribution':'Google FLEURS contributors','role':'token-decoding parity fixture, no broad accuracy claim'})
        print(language,len(samples),'samples',flush=True)
    (a.output/'dataset.json').write_text(json.dumps({'schema_version':1,'source':'google/fleurs plus CC0 Esetok Kazakh pronunciation','source_revision':DATASET_REVISION,'entries':entries},indent=2)+'\n')
