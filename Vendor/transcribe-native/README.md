# Native GigaAM 600M candidate

This is the maintained local recipe for the `add-gigaam-600m-transcribe-fork`
change. It is not a hosted fork, accepted dependency, model release, or VoicePen
app integration. Model files, speech, tensor dumps and built frameworks stay
under ignored `.local/asr-quality/`. No inference Python/MLX environment ships.

`pins.json` binds upstream, ggml, checkpoint, converter environment, language
metadata, stock25 policy, scoring inputs and macOS target. There is no fork Git
commit yet; the archive digest plus ordered patch digests identify the source.
`PATCHES.md` describes ownership, updates and rollback. Full license provenance
is in `licenses/README.md`. `schema/artifact-manifest.schema.json` describes the
package manifest, including exact source/model identity and content checksums.

## Prepare and build

Run from the VoicePen repository root. Python commands use `uv --native-tls
run --no-project --python 3.13`; add `--offline` when dependencies are cached.
Commands that use home caches or Xcode need execution outside the workspace
sandbox. Never run CoreML compilation. Keep heavy jobs sequential and use two
build jobs and four CPU inference threads.

Obtain the upstream archive for commit
`1dc22facfc931e2f8adb43924b0e38b9c46f83c7` from
`https://codeload.github.com/handy-computer/transcribe.cpp/tar.gz/1dc22facfc931e2f8adb43924b0e38b9c46f83c7`.
`prepare.py` rejects archives whose digest differs from `pins.json`, extracts
safely, and applies both checked-in patches in order. It refuses an existing
output directory.

```sh
uv --native-tls run --no-project --python 3.13 \
  Vendor/transcribe-native/tools/prepare.py \
  --archive .local/asr-quality/evaluations/transcribe-cpp-20261019/source.tar.gz \
  --output .local/asr-quality/native-gigaam-600m/source-new

uv --native-tls run --no-project --python 3.13 --with cmake==4.4.4 \
  Vendor/transcribe-native/tools/build.py --cmake cmake \
  --source .local/asr-quality/native-gigaam-600m/source-new \
  --build .local/asr-quality/native-gigaam-600m/build-new --mode framework
```

Use `--mode tests-tools` in another clean build directory for upstream native
unit tests, diagnostic hooks, benchmark and quantizer targets. The tools build
works with examples disabled. `tools/run.py --log PATH --timeout 600 -- COMMAND`
provides an explicit watchdog, records process exit/elapsed time, and cleans
only its own child process group on failure. Use it for build/test/inference
jobs. `ctest --test-dir BUILD --output-on-failure --parallel 1` runs the native
suite. This does not replace the separately owned VoicePen `make test` loop.

## Convert

The converter promotes the original 824-entry mapping rather than a new model
implementation. It validates the exact source/config digests and vocabulary,
checks all shapes and finite values, reverses 75 Conv1d transforms, checks their
inverse exactly, and writes atomically. The F32 diagnostic artifact promotes
the same F16-valued source weights. It is not a different checkpoint.

```sh
uv --native-tls run --no-project --python 3.13 \
  --with numpy==2.5.4 --with gguf==0.19.0 --with safetensors==0.8.0 \
  Vendor/transcribe-native/tools/convert.py \
  --source .local/asr-quality/evaluations/gigaam-20261019/models/fp16 \
  --upstream .local/asr-quality/native-gigaam-600m/source-new \
  --output .local/asr-quality/native-gigaam-600m/models/new-F16.gguf
```

Use `--storage F32` only for numerical diagnostics. Repeat a conversion into a
new output and compare SHA-256 digests for reproducibility. The generated JSON
records each tensor, layout, storage, source provenance and output digest.
Only independently accepted precision variants may become consumer assets.
The historical Q8 result is slower and has regressions; it is experimental.

## Callable contract

The dynamic framework and Clang module are `VoicePenGigaAM`. Public C functions
are `transcribe_*`; `transcribe.h` is the explicit module header. Remaining
public C headers and the upstream ABI hash are packaged alongside it.

The profile is `gigaam-multilingual-large-ctc`, version 1. Capabilities expose
`ru/en/kk/ky/uz`, 16 kHz mono Float32 input, automatic multilingual greedy CTC,
long-form processing, cancellation, and text-only results. Forced language,
translation, prompt/vocabulary/prefix controls, speculative decoding, streaming
and explicit timestamp/PNC/ITN controls are rejected. Use the C parameter-init
functions. In particular default `language=NULL`, `timestamps=AUTO` and
`spec_k_drafts=-1` are valid. Serialize compute across sessions of one model.
Free all sessions before their model. A canceled request does not prevent reuse.

Metal is required for the supported profile. AUTO resolves to Metal; CPU is a
diagnostic option in a validation build. Every arithmetic encoder graph node
is checked after scheduling. Views are metadata. The frontend, CTC projection
and search remain on the host. Logs report stage placement and retained/context
spans; the C timing API reports mel/encoder/decode timing. The stock25 policy
uses at most 625 encoder frames with up to 50 context frames each side,
stitches retained frames, and collapses CTC once. Supported builds compile out
the whole-input/GPU-head research overrides. Generic scalar-string model
metadata exposes the policy, source revision, source weight digest and storage.

## Numerical and corpus checks

```sh
uv --native-tls run --no-project --python 3.13 \
  --with numpy==2.5.4 --with gguf==0.19.0 --with safetensors==0.8.0 \
  --with jiwer==4.0.0 -m unittest discover -s Vendor/transcribe-native/tests -v
```

`tools/reference.py` is an independent matched-F32 MLX stock-window oracle.
It computes the full-recording frontend once, uses window-local rotary
positions, retains the same encoder-frame spans, and applies one CTC collapse.
`tools/compare_stages.py` requires the frontend, subsampling, all 24 blocks,
final encoder and logits, plus exact collapsed token IDs. Missing or nonfinite
checkpoints fail. Thresholds are the frozen design limits, not observed scores.

`tools/benchmark.py` validates the full frozen dataset/audio digests, runs the C
client three times after a same-shape warmup per recording, and saves cold model
load, warmed distributions, stage timings, peak RSS and Metal graph proof.
`--package` additionally binds the exact package/model digests. The C client
uses saved ASR inputs as-is, without VoicePen preprocessing. `tools/evaluate.py`
requires exact full-corpus membership and compares every F16 transcript to both
the matched-window oracle and frozen research stock25 outputs. All four frozen
protocols and word/character edit alignments remain in the private report.
The report's corpus acceptance flag does not accept the whole native package.

`tools/fixture_parity.py` runs every block on the public/synthetic set with
`--storage F16 --backend Metal` or `--storage F32 --backend CPU`. The latter
is a graph/layout diagnostic. Keep F32/Metal results separate: pinned ggml's
`kernel_mul_mm_f32_f32` uses half matrix operands, despite F32 tensor storage.
An explicitly failed F32/Metal run stays failed; numerical limits do not change.
`tools/boundary_parity.py` compares real speech at 624/625/626 encoder frames
against the independent stock-window oracle.

`tools/public_speech.py` prepares four pinned CC-BY-4.0 FLEURS fixtures and
one CC0 Kazakh pronunciation, covering all five advertised languages.
It keeps audio and server responses outside Git and
records attribution/digests. These are token-decoding parity checks, not a
language-wide accuracy claim. `tests/window_ctc.cpp` directly tests the native
planner and blank/repeat collapse across retained boundaries.

## Package and consume

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
uv --native-tls run --no-project --python 3.13 \
  Vendor/transcribe-native/tools/package.py build \
  --source SOURCE --build BUILD --output OUTPUT --model MODEL.gguf

uv --native-tls run --no-project --python 3.13 \
  Vendor/transcribe-native/tools/package.py verify OUTPUT
```

The producer checks hidden internals, public exports, dynamic dependencies,
resource ownership, notices, content hashes and symlink targets. The framework
contains private static ggml and embedded Metal sources. No global Objective-C
resource class is registered, and kernels do not use another bundle, source
checkout, working-directory or process-global resource overrides. Its install
name is relocatable `@rpath/VoicePenGigaAM.framework/Versions/A/VoicePenGigaAM`.
The framework needs LC_UUID on current Apple linkers; disabling UUID made real
consumer linkage fail. Rebuild comparisons must distinguish toolchain UUID
variation from changes to model contents, headers, resources and notices.

Compile `tests/client.c` against the relocated framework and
`tests/swift-client.swift` with `-F FRAMEWORK_DIRECTORY -framework
VoicePenGigaAM`, targeting `arm64-apple-macosx15.0`. Give the executable an
`@executable_path/Frameworks` rpath. Run from a directory outside the checkout
with `PATH=/usr/bin:/bin` to demonstrate that Python/MLX are not runtime
dependencies. The C client covers real Metal load/run/cancel/free/reuse;
the Swift client checks import, defaults and incompatible struct size.
A separate combined Whisper/GigaAM app test is owned by the integration change.

`tools/v3_regression.py` compares all four real v3 checkpoints with a pinned
upstream client on public short speech and the longest private corpus input,
including capabilities, explicit option errors and legacy ignored prompting.
`fixtures/v3-regression.json` pins the public checkpoint revisions/digests.
`tools/link-diagnostics.sh` links the tests/tools static build into an offline
diagnostic dylib. `tools/head_ab.py` promotes the preserved whole-input paired
head experiment against that exact validation build, using the frozen ABI
bindings and scoring policies. Its watchdog log must be passed as
`--native-log`; measured calls exclude dumps, and the report keeps synchronous
readback, graph and host decode timings separate. It does not change the
shipping host head or make whole-input a supported policy.

Run `tools/head_probe.py` once per head in separate processes, giving each
an output directory before native initialization. The upstream dump directory
is cached at initialization; changing it between timed calls does not enable
dumps. `tools/head_report.py` combines those untimed tensor probes with saved
paired calls. A postprocessing failure does not require repeating complete
successful pairs. Keep the failed attempt and its original source/log.

The manifest remains `acceptance=unaccepted` until every applicable gate passes
and ADR-0013 is reviewed. `tools/update_gate.py` rejects missing, failing or
wrong-pin reports, including stale converter/reference/validation-input
digests even when artifact bytes are unchanged. It does not turn skipped
private jobs into acceptance.
The separate local attestation at
`.local/asr-quality/native-gigaam-600m/host-local-acceptance.json` accepts the
exact reviewed F16 pair only on the tested macOS 26.6.2 host. Actual macOS 15
packaged-client execution remains unverified; deployment-target metadata
alone does not close that distribution gate. The static GGUF's content and
quality verdict is recorded independently. Neither verdict authorizes
publication, and the canonical candidate manifest remains byte-immutable.
No script here publishes, commits, rewires VoicePen, or changes its defaults.
