#include <VoicePenGigaAM/transcribe.h>
#include <whisper/whisper.h>
#include <limits.h>
#include <math.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool abort_now(void * unused) { (void) unused; return true; }

static char * whisper_text(struct whisper_context * context) {
    size_t size = 1;
    for (int i = 0; i < whisper_full_n_segments(context); ++i) size += strlen(whisper_full_get_segment_text(context, i));
    char * text = calloc(size, 1);
    if (!text) return NULL;
    for (int i = 0; i < whisper_full_n_segments(context); ++i) strcat(text, whisper_full_get_segment_text(context, i));
    return text;
}

static int pair(const char * giga_path, const char * whisper_path, const float * samples, int count, int giga_first, char ** giga_text, char ** other_text) {
    struct transcribe_model * model = NULL;
    struct transcribe_session * session = NULL;
    struct whisper_context * whisper = NULL;
    struct transcribe_model_load_params load;
    transcribe_model_load_params_init(&load);
    load.backend = TRANSCRIBE_BACKEND_METAL;
    struct whisper_context_params whisper_load = whisper_context_default_params();
    whisper_load.use_gpu = true;
    whisper_load.flash_attn = true;
    int result = 1;
    if (giga_first) {
        if (transcribe_model_load_file(giga_path, &load, &model) != TRANSCRIBE_OK) goto cleanup;
        whisper = whisper_init_from_file_with_params(whisper_path, whisper_load);
    } else {
        whisper = whisper_init_from_file_with_params(whisper_path, whisper_load);
        if (transcribe_model_load_file(giga_path, &load, &model) != TRANSCRIBE_OK) goto cleanup;
    }
    if (!whisper || !model || strncmp(transcribe_model_backend(model), "MTL", 3)) goto cleanup;
    Class resource_class = objc_getClass("GGMLMetalClass");
    const char * resource_image = resource_class ? class_getImageName(resource_class) : NULL;
    if (resource_class && (!resource_image || !strstr(resource_image, "whisper.framework/"))) goto cleanup;
    struct transcribe_session_params session_params;
    transcribe_session_params_init(&session_params);
    session_params.n_threads = 4;
    if (transcribe_session_init(model, &session_params, &session) != TRANSCRIBE_OK) goto cleanup;
    struct transcribe_run_params run;
    transcribe_run_params_init(&run);
    run.timestamps = TRANSCRIBE_TIMESTAMPS_NONE;
    if (transcribe_run(session, samples, count, &run) != TRANSCRIBE_OK) goto cleanup;
    *giga_text = strdup(transcribe_full_text(session));
    if (!*giga_text || !**giga_text) goto cleanup;
    transcribe_set_abort_callback(session, abort_now, NULL);
    if (transcribe_run(session, samples, count, &run) != TRANSCRIBE_ERR_ABORTED) goto cleanup;
    transcribe_set_abort_callback(session, NULL, NULL);
    if (transcribe_run(session, samples, count, &run) != TRANSCRIBE_OK || strcmp(*giga_text, transcribe_full_text(session))) goto cleanup;
    struct whisper_full_params decode = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    decode.n_threads = 4;
    decode.no_context = true;
    decode.no_timestamps = true;
    decode.print_progress = false;
    decode.print_realtime = false;
    decode.print_timestamps = false;
    decode.language = "auto";
    if (whisper_full(whisper, decode, samples, count)) goto cleanup;
    *other_text = whisper_text(whisper);
    if (!*other_text || !**other_text) goto cleanup;
    result = 0;
cleanup:
    transcribe_session_free(session);
    transcribe_model_free(model);
    if (whisper) whisper_free(whisper);
    return result;
}

int main(int argc, char ** argv) {
    if (argc != 4) return 64;
    FILE * input = fopen(argv[3], "rb");
    if (!input || fseek(input, 0, SEEK_END)) return 65;
    long bytes = ftell(input);
    if (bytes <= 0 || bytes % sizeof(float) || bytes / sizeof(float) > INT_MAX || fseek(input, 0, SEEK_SET)) return 65;
    int count = (int) (bytes / sizeof(float));
    float * samples = malloc((size_t) bytes);
    if (!samples || fread(samples, sizeof(float), (size_t) count, input) != (size_t) count) return 65;
    fclose(input);
    for (int i = 0; i < count; ++i) if (!isfinite(samples[i])) return 65;
    char * giga[2] = {NULL, NULL};
    char * whisper[2] = {NULL, NULL};
    int result = pair(argv[1], argv[2], samples, count, 1, &giga[0], &whisper[0]);
    if (!result) result = pair(argv[1], argv[2], samples, count, 0, &giga[1], &whisper[1]);
    if (!result && (strcmp(giga[0], giga[1]) || strcmp(whisper[0], whisper[1]))) result = 2;
    if (!result) printf("{\"orders\":2,\"gigaam_equal\":true,\"whisper_equal\":true,\"gigaam_cancel_reuse\":true,\"resource_classes_isolated\":true,\"ggml_resource_class_present\":%s,\"input_samples\":%d}\n", objc_getClass("GGMLMetalClass") ? "true" : "false", count);
    for (int i = 0; i < 2; ++i) { free(giga[i]); free(whisper[i]); }
    free(samples);
    return result;
}
