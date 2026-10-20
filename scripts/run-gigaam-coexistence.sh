#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gigaam="${1:?Usage: run-gigaam-coexistence.sh GIGAAM_GGUF WHISPER_BIN MONO_16K_FLOAT32_PCM OUTPUT_DIR}"
whisper="${2:?WHISPER_BIN required}"
pcm="${3:?MONO_16K_FLOAT32_PCM required}"
output="${4:?OUTPUT_DIR required}"
[[ ! -e "$output" ]] || { printf 'Refusing to overwrite coexistence evidence\n' >&2; exit 73; }
mkdir -p "$output/Frameworks"
output="$(cd "$output" && pwd)"
cp -cR "$repo_root/Vendor/transcribe.spm/Artifacts/VoicePenGigaAM.xcframework/macos-arm64/VoicePenGigaAM.framework" "$output/Frameworks/VoicePenGigaAM.framework"
cp -cR "$repo_root/.build/out/Products/Debug/whisper.framework" "$output/Frameworks/whisper.framework"
native="$output/Frameworks/VoicePenGigaAM.framework/VoicePenGigaAM"
nm -gU "$native" > "$output/exports.txt"
if rg '_ggml_|GGMLMetalClass' "$output/exports.txt"; then
  printf 'Private native symbols escaped\n' >&2
  exit 65
fi
nm -U "$native" | awk '/_OBJC_(META)?CLASS_\$_/ {print}' > "$output/objc-classes.txt"
[[ ! -s "$output/objc-classes.txt" ]] || { printf 'Unexpected global native Objective-C classes\n' >&2; exit 65; }
otool -L "$native" > "$output/dependencies.txt"
xcrun clang -arch arm64 -mmacosx-version-min=15.0 -O2 \
  -F "$output/Frameworks" -framework VoicePenGigaAM -framework whisper -lobjc \
  -Wl,-rpath,@executable_path/Frameworks \
  "$repo_root/Tools/GigaAMIntegration/coexistence.c" -o "$output/coexistence"
(
  cd "$output"
  env -u DYLD_LIBRARY_PATH -u GGML_METAL_PATH_RESOURCES -u GGML_METAL_PATH_SOURCE PATH=/usr/bin:/bin \
    /usr/bin/perl -e 'alarm 120; exec @ARGV' "$output/coexistence" "$gigaam" "$whisper" "$pcm"
) > "$output/run.log" 2>&1
if rg 'Class .* is implemented in both' "$output/run.log"; then
  printf 'Duplicate Objective-C runtime class\n' >&2
  exit 65
fi
rg '^\{"orders"' "$output/run.log" > "$output/result.json"
printf 'Verified both native load orders and cancellation/reuse: %s\n' "$output/result.json"
