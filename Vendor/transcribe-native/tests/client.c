#include "transcribe.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

extern void voicepen_fault_arm(void) __attribute__((weak_import));
extern void voicepen_fault_disarm(void) __attribute__((weak_import));

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void json_string(const char *s) {
    putchar('"');
    for (const unsigned char *p=(const unsigned char *)s;*p;p++) {
        if (*p=='"'||*p=='\\') {putchar('\\');putchar(*p);}
        else if (*p<32) printf("\\u%04x",*p);
        else putchar(*p);
    }
    putchar('"');
}
static float *read_pcm(const char *path,int *count) {
    FILE *f=fopen(path,"rb"); if (!f) return NULL;
    fseek(f,0,SEEK_END); long size=ftell(f); rewind(f);
    if (size<=0||size%4||size/4>2147483647) {fclose(f);return NULL;}
    float *pcm=malloc((size_t)size);
    if (!pcm||fread(pcm,1,(size_t)size,f)!=(size_t)size) {free(pcm);fclose(f);return NULL;}
    fclose(f); *count=(int)(size/4);return pcm;
}
static bool abort_checkpoint(void *data) { int *polls=data; return ++*polls>=4; }
static int contracts(struct transcribe_model *m,struct transcribe_session *s,const float *pcm,int n) {
    struct transcribe_capabilities c;transcribe_capabilities_init(&c);
    assert(transcribe_model_get_capabilities(m,&c)==TRANSCRIBE_OK);
    assert(c.n_languages==5 && c.max_timestamp_kind==TRANSCRIBE_TIMESTAMPS_NONE);
    assert(!c.supports_translate && !c.supports_language_detect && !c.supports_streaming);
    const char *expected[]={"ru","en","kk","ky","uz"};
    for(int i=0;i<5;i++) assert(strcmp(c.languages[i],expected[i])==0);
    struct transcribe_run_params p;transcribe_run_params_init(&p);
    assert(p.language==NULL && p.timestamps==TRANSCRIBE_TIMESTAMPS_AUTO);
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_OK);
    char *previous=strdup(transcribe_full_text(s));
    p.language="ru";assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_UNSUPPORTED_LANGUAGE);
    assert(strcmp(previous,transcribe_full_text(s))==0);free(previous);
    transcribe_run_params_init(&p);p.timestamps=TRANSCRIBE_TIMESTAMPS_TOKEN;
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_UNSUPPORTED_TIMESTAMPS);
    transcribe_run_params_init(&p);p.task=TRANSCRIBE_TASK_TRANSLATE;
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_UNSUPPORTED_TASK);
    transcribe_run_params_init(&p);p.prefix="test";
    assert(transcribe_run(s,pcm,n,&p)!=TRANSCRIBE_OK);
    transcribe_run_params_init(&p);p.prompt="test";
    assert(transcribe_run(s,pcm,n,&p)!=TRANSCRIBE_OK);
    transcribe_run_params_init(&p);p.pnc=TRANSCRIBE_PNC_MODE_ON;
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_UNSUPPORTED_PNC);
    transcribe_run_params_init(&p);p.itn=TRANSCRIBE_ITN_MODE_ON;
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_UNSUPPORTED_ITN);
    transcribe_run_params_init(&p);p.spec_k_drafts=2;
    assert(transcribe_run(s,pcm,n,&p)==TRANSCRIBE_ERR_NOT_IMPLEMENTED);
    struct transcribe_stream_params stream;transcribe_stream_params_init(&stream);
    assert(transcribe_stream_begin(s,NULL,&stream)!=TRANSCRIBE_OK);
    assert(transcribe_run(s,NULL,n,NULL)==TRANSCRIBE_ERR_INVALID_ARG);
    assert(transcribe_run(s,pcm,0,NULL)==TRANSCRIBE_ERR_INVALID_ARG);
    assert(transcribe_run(s,pcm,100,NULL)==TRANSCRIBE_ERR_INVALID_ARG);
    float invalid[320]={0};invalid[50]=NAN;
    assert(transcribe_run(s,invalid,320,NULL)==TRANSCRIBE_ERR_INVALID_ARG);
    invalid[50]=INFINITY;assert(transcribe_run(s,invalid,320,NULL)==TRANSCRIBE_ERR_INVALID_ARG);
    float silence[16000]={0};
    assert(transcribe_run(s,silence,16000,NULL)==TRANSCRIBE_OK);
    assert(strlen(transcribe_full_text(s))==0);
    int polls=0;transcribe_set_abort_callback(s,abort_checkpoint,&polls);
    assert(transcribe_run(s,pcm,n,NULL)==TRANSCRIBE_ERR_ABORTED);
    assert(polls>=4 && transcribe_was_aborted(s));
    assert(strlen(transcribe_full_text(s))==0);
    transcribe_set_abort_callback(s,NULL,NULL);
    assert(transcribe_run(s,pcm,n,NULL)==TRANSCRIBE_OK);
    assert(!transcribe_was_aborted(s));
    puts("{\"contracts_pass\":true,\"cancellation_checkpoint_polls\":4}");
    return 0;
}
int main(int argc,char **argv) {
    if(argc<3) return 64;
    assert(transcribe_init_backends_default()==TRANSCRIBE_OK);
    struct transcribe_model_load_params lp;transcribe_model_load_params_init(&lp);
    lp.backend=TRANSCRIBE_BACKEND_METAL;
    if(argc>4 && strcmp(argv[4],"CPU")==0) lp.backend=TRANSCRIBE_BACKEND_CPU;
    struct transcribe_model *m=NULL;
    double start=now();int status=transcribe_model_load_file(argv[1],&lp,&m);double load=now()-start;
    if (status!=TRANSCRIBE_OK) {
        assert(m==NULL);
        if (argc>3 && strcmp(argv[3],"--expect-load-failure")==0) {
            printf("{\"load_rejection_pass\":true,\"status\":%d}\n",status);return 0;
        }
        if (argc>3 && strcmp(argv[3],"--expect-backend-failure")==0) {
            assert(status==TRANSCRIBE_ERR_BACKEND);puts("{\"required_metal_failure_pass\":true}");return 0;
        }
        fprintf(stderr,"load_status=%d\n",status);return status;
    }
    if (argc>3 && (strcmp(argv[3],"--expect-load-failure")==0 || strcmp(argv[3],"--expect-backend-failure")==0)) {
        transcribe_model_free(m);fprintf(stderr,"unexpected successful model load\n");return 125;
    }
    printf("{\"actual_backend\":");json_string(transcribe_model_backend(m));puts("}");
    struct transcribe_session_params sp;transcribe_session_params_init(&sp);sp.n_threads=4;
    struct transcribe_session *s=NULL;assert(transcribe_session_init(m,&sp,&s)==TRANSCRIBE_OK);
    int n=0;float *pcm=read_pcm(argv[2],&n);assert(pcm);
    if(argc>3 && strcmp(argv[3],"--contracts")==0) status=contracts(m,s,pcm,n);
    else if(argc>3 && strcmp(argv[3],"--fault-oom")==0) {
        assert(voicepen_fault_arm && voicepen_fault_disarm);
        voicepen_fault_arm();status=transcribe_run(s,pcm,n,NULL);voicepen_fault_disarm();
        assert(status==TRANSCRIBE_ERR_OOM);
        assert(transcribe_run(s,pcm,n,NULL)==TRANSCRIBE_OK);
        status=0;puts("{\"metal_allocation_failure_and_reuse_pass\":true}");
    }
    else {
        int legacy=argc>3 && strcmp(argv[3],"--legacy-contracts")==0;
        int repeats=legacy?1:(argc>3?atoi(argv[3]):3);
        assert(repeats>0);
        if(legacy) {
            struct transcribe_capabilities c;transcribe_capabilities_init(&c);
            assert(transcribe_model_get_capabilities(m,&c)==TRANSCRIBE_OK);
            struct transcribe_run_params invalid;transcribe_run_params_init(&invalid);
            invalid.task=TRANSCRIBE_TASK_TRANSLATE;
            int translate=transcribe_run(s,pcm,n,&invalid);
            transcribe_run_params_init(&invalid);invalid.language="en";
            int language=transcribe_run(s,pcm,n,&invalid);
            transcribe_run_params_init(&invalid);invalid.prompt="legacy ignored prompt";
            int prompt=transcribe_run(s,pcm,n,&invalid);
            printf("{\"legacy_prompt_status\":%d,\"text\":",prompt);json_string(transcribe_full_text(s));puts("}");
            printf("{\"legacy_contracts\":true,\"sample_rate\":%d,\"max_timestamp_kind\":%d,\"max_audio_ms\":%lld,\"language_detect\":%d,\"translate\":%d,\"streaming\":%d,\"spec_decode\":%d,\"translate_status\":%d,\"language_status\":%d,\"invalid_audio_status\":%d,\"languages\":[",c.native_sample_rate,c.max_timestamp_kind,(long long)c.max_audio_ms,c.supports_language_detect,c.supports_translate,c.supports_streaming,c.supports_spec_decode,translate,language,transcribe_run(s,NULL,n,NULL));
            for(int i=0;i<c.n_languages;i++) {if(i)putchar(',');json_string(c.languages[i]);}
            puts("]}");
        }
        assert(transcribe_run(s,pcm,n,NULL)==TRANSCRIBE_OK);
        for(int i=0;i<repeats;i++) {
            start=now();status=transcribe_run(s,pcm,n,NULL);double wall=now()-start;
            struct transcribe_timings tm;transcribe_timings_init(&tm);assert(transcribe_get_timings(s,&tm)==TRANSCRIBE_OK);
            struct rusage usage;getrusage(RUSAGE_SELF,&usage);
            printf("{\"repeat\":%d,\"status\":%d,\"native_wall_s\":%.9f,\"model_load_s\":%.9f,\"mel_ms\":%.6f,\"encode_ms\":%.6f,\"decode_ms\":%.6f,\"peak_rss_bytes\":%ld,\"sample_count\":%d,\"text\":",i,status,wall,load,tm.mel_ms,tm.encode_ms,tm.decode_ms,usage.ru_maxrss,n);
            json_string(transcribe_full_text(s));printf(",\"token_ids\":[");
            for(int token_index=0;token_index<transcribe_n_tokens(s);token_index++) {
                struct transcribe_token token;transcribe_token_init(&token);
                assert(transcribe_get_token(s,token_index,&token)==TRANSCRIBE_OK);
                printf("%s%d",token_index?",":"",token.id);
            }
            puts("]}");fflush(stdout);
            if(status!=TRANSCRIBE_OK) break;
        }
    }
    free(pcm);transcribe_session_free(s);transcribe_model_free(m);return status;
}
