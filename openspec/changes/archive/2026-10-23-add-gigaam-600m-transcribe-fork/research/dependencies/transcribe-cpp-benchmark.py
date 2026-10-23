import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / 'gigaam-20261019'
CORPUS = json.loads((PREVIOUS / 'corpus.json').read_text())
SNAPSHOT = json.loads((ROOT.parents[1] / 'exports' / CORPUS['snapshot_id'] / 'dataset.json').read_text())
ENTRIES = {entry['id']: entry for entry in SNAPSHOT['entries']}

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

class Load(C.Structure):
    _fields_ = [('struct_size', C.c_uint64), ('backend', C.c_int), ('device', C.c_void_p)]

class Session(C.Structure):
    _fields_ = [('struct_size', C.c_uint64), ('n_threads', C.c_int), ('kv_type', C.c_int), ('n_ctx', C.c_int32)]

class Ext(C.Structure):
    _fields_ = [('size', C.c_uint64), ('kind', C.c_uint32)]

class Whisper(C.Structure):
    _fields_ = [('ext', Ext), ('initial_prompt', C.c_char_p), ('prompt_tokens', C.POINTER(C.c_int32)),
                ('n_prompt_tokens', C.c_size_t), ('prompt_condition', C.c_int),
                ('condition_on_prev_tokens', C.c_bool), ('max_prev_context_tokens', C.c_int32),
                ('temperature', C.c_float), ('temperature_inc', C.c_float),
                ('compression_ratio_thold', C.c_float), ('logprob_thold', C.c_float),
                ('no_speech_thold', C.c_float), ('seed', C.c_uint32), ('max_initial_timestamp', C.c_float)]

class Run(C.Structure):
    _fields_ = [('struct_size', C.c_uint64), ('task', C.c_int), ('timestamps', C.c_int),
                ('pnc', C.c_int), ('itn', C.c_int), ('diarize', C.c_int), ('language', C.c_char_p),
                ('target_language', C.c_char_p), ('keep_special_tags', C.c_bool), ('family', C.POINTER(Ext)),
                ('spec_k_drafts', C.c_int32), ('vocabulary', C.POINTER(C.c_char_p)),
                ('n_vocabulary', C.c_int32), ('prompt', C.c_char_p), ('prefix', C.c_char_p)]

class Timings(C.Structure):
    _fields_ = [('struct_size', C.c_uint64), ('load_ms', C.c_float), ('mel_ms', C.c_float),
                ('encode_ms', C.c_float), ('decode_ms', C.c_float)]

def worker(name):
    libpath = next((ROOT / 'build').rglob('libtranscribe.dylib'))
    lib = C.CDLL(str(libpath))
    def fn(name, args, result=C.c_int):
        function = getattr(lib, name)
        function.argtypes, function.restype = args, result
        return function
    initialize = fn('transcribe_init_backends_default', [])
    init_load = fn('transcribe_model_load_params_init', [C.POINTER(Load)], None)
    init_session = fn('transcribe_session_params_init', [C.POINTER(Session)], None)
    init_run = fn('transcribe_run_params_init', [C.POINTER(Run)], None)
    init_whisper = fn('transcribe_whisper_run_ext_init', [C.POINTER(Whisper)], None)
    init_timings = fn('transcribe_timings_init', [C.POINTER(Timings)], None)
    load_model = fn('transcribe_model_load_file', [C.c_char_p, C.POINTER(Load), C.POINTER(C.c_void_p)])
    new_session = fn('transcribe_session_init', [C.c_void_p, C.POINTER(Session), C.POINTER(C.c_void_p)])
    infer = fn('transcribe_run', [C.c_void_p, C.POINTER(C.c_float), C.c_int, C.POINTER(Run)])
    get_text = fn('transcribe_full_text', [C.c_void_p], C.c_char_p)
    get_timings = fn('transcribe_get_timings', [C.c_void_p, C.POINTER(Timings)])
    backend = fn('transcribe_model_backend', [C.c_void_p], C.c_char_p)
    free_session = fn('transcribe_session_free', [C.c_void_p], None)
    free_model = fn('transcribe_model_free', [C.c_void_p], None)
    version = fn('transcribe_version', [], C.c_char_p)
    assert initialize() == 0
    whisper = name == 'whisper-turbo-q8'
    if whisper:
        modelpath = Path(json.loads((PREVIOUS / 'whisper-current/asr/metadata.json').read_text())['model'])
    else:
        modelpath = ROOT / (name + '-Q8_0.gguf')
        metadata = json.loads((ROOT / ('ctc-source.json' if 'ctc' in name else 'rnnt-source.json')).read_text())
        expected = next(item for item in metadata['siblings'] if item['rfilename'] == modelpath.name)
        assert modelpath.stat().st_size == expected['size']
        assert hashlib.sha256(modelpath.read_bytes()).hexdigest() == expected['lfs']['sha256']
    model_sha = hashlib.sha256(modelpath.read_bytes()).hexdigest()
    lp, sp, rp, wp = Load(), Session(), Run(), Whisper()
    init_load(C.byref(lp)); lp.backend = 2
    init_session(C.byref(sp)); sp.n_threads = 4
    init_run(C.byref(rp)); rp.language = b'ru'; rp.timestamps = 0
    # TRANSCRIBE_TIMESTAMPS_NONE is checked against the pinned header in prepare.
    prompt = (PREVIOUS / 'whisper-current/asr/prompt.txt').read_bytes()
    if whisper:
        init_whisper(C.byref(wp))
        wp.initial_prompt = prompt
        wp.condition_on_prev_tokens = False
        wp.seed = 20261019
        rp.family = C.pointer(wp.ext)
    model, session = C.c_void_p(), C.c_void_p()
    started = time.monotonic()
    status = load_model(str(modelpath).encode(), C.byref(lp), C.byref(model))
    assert status == 0, ('model load', status)
    load_s = time.monotonic() - started
    try:
        assert new_session(model, C.byref(sp), C.byref(session)) == 0
        actual_backend = backend(model).decode()
        assert 'MTL' in actual_backend.upper() or 'METAL' in actual_backend.upper(), actual_backend
        def execute(samples):
            started = time.monotonic()
            status = infer(session, samples.ctypes.data_as(C.POINTER(C.c_float)), len(samples), C.byref(rp))
            elapsed = time.monotonic() - started
            timings = Timings(); init_timings(C.byref(timings))
            assert get_timings(session, C.byref(timings)) == 0
            return {'status': status, 'text': (get_text(session) or b'').decode(), 'native_wall_s': elapsed,
                    **{field: getattr(timings, field) for field in ['mel_ms', 'encode_ms', 'decode_ms']}}
        wp.initial_prompt = None
        warmup = execute(np.zeros(16000, dtype=np.float32))
        wp.initial_prompt = prompt if whisper else None
        assert warmup['status'] == 0, warmup
        folder = ROOT / name; folder.mkdir(exist_ok=True)
        write(folder / 'metadata.json', {'model': str(modelpath), 'model_sha256': model_sha,
              'engine_commit': '1dc22facfc931e2f8adb43924b0e38b9c46f83c7', 'version': version().decode(),
              'backend': actual_backend, 'threads': 4, 'model_load_s': load_s, 'warmup': warmup,
              'language': 'ru', 'timestamps': 'none', 'repeats': 3, 'prompt': prompt.decode() if whisper else None,
              'whisper_condition_on_prev_tokens': False if whisper else None, 'whisper_seed': wp.seed if whisper else None,
              'whisper_temperature_inc': wp.temperature_inc if whisper else None})
        with (folder / 'runs.jsonl').open('x') as output:
            for clip in CORPUS['selected']:
                sid = clip['sample_id']; audio = Path(clip['selected_audio_path'])
                assert hashlib.sha256(audio.read_bytes()).hexdigest() == ENTRIES[sid]['sha256']
                samples, sr = sf.read(audio, dtype='float32')
                assert sr == 16000 and samples.ndim == 1 and np.isfinite(samples).all()
                assert len(samples) == round(ENTRIES[sid]['duration'] * sr)
                for repeat in range(3):
                    row = {**execute(samples), 'sample_id': sid, 'repeat': repeat,
                           'sample_count': len(samples), 'audio_duration_s': len(samples) / sr}
                    output.write(json.dumps(row, ensure_ascii=False) + '\n'); output.flush()
                    print(name, sid, repeat, row['status'], round(row['native_wall_s'], 3), flush=True)
                    assert row['status'] == 0, row
    finally:
        free_session(session)
        free_model(model)

def supervise(name):
    folder = ROOT / name; folder.mkdir(exist_ok=True)
    command = [sys.executable, str(Path(__file__).resolve()), 'worker', name]
    started = time.monotonic()
    with (folder / 'progress.log').open('w') as out, (folder / 'native.log').open('w') as err:
        process = subprocess.Popen(command, stdout=out, stderr=err, start_new_session=True)
        try:
            process.wait(timeout=360)
        finally:
            if process.poll() is None:
                import signal
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait()
            result = {'command': command, 'pid': process.pid, 'exit_code': process.returncode,
                      'elapsed_s': time.monotonic() - started}
            write(folder / 'process.json', result)
    print(json.dumps(result), flush=True)
    assert process.returncode == 0, name

if __name__ == '__main__':
    if sys.argv[1] == 'worker': worker(sys.argv[2])
    else:
        for name in ['gigaam-v3-e2e-ctc', 'gigaam-v3-e2e-rnnt', 'whisper-turbo-q8']:
            supervise(name)
