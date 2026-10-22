#include "transcribe.h"
#include <assert.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
static void json_string(const char *text) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) {
        if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
        else if (*p < 32) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}
static float *read_pcm(const char *path, int *count) {
    FILE *file = fopen(path, "rb"); assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    long size = ftell(file);
    assert(size > 0 && size % 4 == 0 && size / 4 <= INT_MAX);
    rewind(file);
    float *pcm = malloc((size_t)size); assert(pcm);
    assert(fread(pcm, 1, (size_t)size, file) == (size_t)size);
    fclose(file);
    *count = (int)(size / 4);
    for (int i = 0; i < *count; ++i) assert(isfinite(pcm[i]));
    return pcm;
}
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "Usage: confidence-client MODEL INPUTS.tsv REPEATS\n"); return 64; }
    const int repeats = atoi(argv[3]); assert(repeats > 0 && repeats <= 5);
    struct transcribe_model_load_params load; transcribe_model_load_params_init(&load);
    load.backend = TRANSCRIBE_BACKEND_METAL;
    struct transcribe_model *model = NULL;
    assert(transcribe_model_load_file(argv[1], &load, &model) == TRANSCRIBE_OK);
    struct transcribe_session_params params; transcribe_session_params_init(&params);
    params.n_threads = 4;
    struct transcribe_session *session = NULL;
    assert(transcribe_session_init(model, &params, &session) == TRANSCRIBE_OK);
    FILE *list = fopen(argv[2], "r"); assert(list);
    char *line = NULL; size_t capacity = 0;
    while (getline(&line, &capacity, list) >= 0) {
        line[strcspn(line, "\r\n")] = 0;
        char *path = strchr(line, '\t'); assert(path); *path++ = 0;
        int count = 0; float *pcm = read_pcm(path, &count);
        struct transcribe_run_params run; transcribe_run_params_init(&run);
        run.timestamps = TRANSCRIBE_TIMESTAMPS_NONE;
        for (int repeat = -1; repeat < repeats; ++repeat) {
            double start = now();
            assert(transcribe_run(session, pcm, count, &run) == TRANSCRIBE_OK);
            double native_seconds = now() - start;
            if (repeat < 0) continue;
            printf("{\"id\":"); json_string(line);
            printf(",\"runtime\":"); json_string(transcribe_version_commit());
            printf(",\"repeat\":%d,\"samples\":%d,\"native_seconds\":%.9f,\"text\":", repeat, count, native_seconds);
            json_string(transcribe_full_text(session)); printf(",\"tokens\":[");
            const int n = transcribe_n_tokens(session);
            for (int i = 0; i < n; ++i) {
                struct transcribe_token token; transcribe_token_init(&token);
                assert(transcribe_get_token(session, i, &token) == TRANSCRIBE_OK && token.text);
                if (i) putchar(',');
                printf("{\"id\":%d,\"t0\":%lld,\"t1\":%lld,\"p\":", token.id, (long long)token.t0_ms, (long long)token.t1_ms);
                if (isfinite(token.p)) printf("%.9g", token.p); else printf("null");
                printf(",\"text\":"); json_string(token.text); putchar('}');
            }
            printf("]}\n"); fflush(stdout);
        }
        free(pcm);
    }
    free(line); fclose(list);
    transcribe_session_free(session); transcribe_model_free(model);
    return 0;
}
