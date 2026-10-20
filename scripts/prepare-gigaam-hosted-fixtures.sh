#!/usr/bin/env bash
set -euo pipefail
model_entry="${1:?Usage: prepare-gigaam-hosted-fixtures.sh MODEL_ENTRY GIGAAM_GGUF WHISPER_BIN AUDIO_WAV OUTPUT_DIR}"
gigaam="${2:?GIGAAM_GGUF required}"
whisper="${3:?WHISPER_BIN required}"
audio="${4:?AUDIO_WAV required}"
output="${5:?OUTPUT_DIR required}"
[[ ! -e "$output/config.json" ]] || { printf 'Refusing to overwrite hosted fixtures\n' >&2; exit 73; }
mkdir -p "$output/whisper"
output="$(cd "$output" && pwd)"
cp -c "$gigaam" "$output/gigaam-600m-F16.gguf"
cp -c "$whisper" "$output/whisper/$(basename "$whisper")"
cp "$model_entry" "$output/model-manifest-entry.json"
cp "$audio" "$output/input.wav"
jq -n --arg entry "$output/model-manifest-entry.json" --arg giga "$output/gigaam-600m-F16.gguf" --arg whisper "$output/whisper/$(basename "$whisper")" --arg audio "$output/input.wav" '{modelEntry:$entry,gigaAMModel:$giga,whisperModel:$whisper,audio:$audio}' > "$output/config.json"
printf 'Prepared isolated hosted fixtures at %s\n' "$output"
