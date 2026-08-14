#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-}"
source_dir="${VOICEPEN_MODEL_ASSET_SOURCE_DIR:-}"

if [[ -z "$output_dir" ]]; then
  printf 'Usage: %s OUTPUT_DIR\n' "$0" >&2
  printf 'Optional: VOICEPEN_MODEL_ASSET_SOURCE_DIR=/path/to/preloaded/files\n' >&2
  exit 64
fi

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
work_dir="$(mktemp -d /private/tmp/voicepen-model-assets.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT

staging_dir="$work_dir/staging"
mkdir -p "$staging_dir/speakerkit-coreml-v1"

asset_names=(
  ggml-large-v3-turbo-q5_0.bin
  ggml-large-v3-turbo-q5_1.bin
  ggml-large-v3-turbo-q8_0.bin
  ggml-large-v3-turbo-encoder.mlmodelc.zip
  speakerkit-coreml-v1.zip
  THIRD_PARTY_NOTICES.md
  model-assets-v1.sha256
)

for asset_name in "${asset_names[@]}"; do
  if [[ -e "$output_dir/$asset_name" ]]; then
    printf 'Refusing to overwrite existing asset: %s\n' "$output_dir/$asset_name" >&2
    exit 73
  fi
done

download() {
  local url="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  curl --fail --location --retry 4 --retry-all-errors --continue-at - \
    --output "$destination" "$url"
}

if [[ -n "$source_dir" ]]; then
  source_dir="$(cd "$source_dir" && pwd)"
  for model_name in \
    ggml-large-v3-turbo-q5_0.bin \
    ggml-large-v3-turbo-q5_1.bin \
    ggml-large-v3-turbo-q8_0.bin; do
    test -f "$source_dir/$model_name"
    COPYFILE_DISABLE=1 ditto --norsrc "$source_dir/$model_name" "$staging_dir/$model_name"
  done
  test -d "$source_dir/ggml-large-v3-turbo-encoder.mlmodelc"
  test -d "$source_dir/speakerkit-coreml-v1"
  COPYFILE_DISABLE=1 ditto --norsrc \
    "$source_dir/ggml-large-v3-turbo-encoder.mlmodelc" \
    "$staging_dir/ggml-large-v3-turbo-encoder.mlmodelc"
  COPYFILE_DISABLE=1 ditto --norsrc \
    "$source_dir/speakerkit-coreml-v1" \
    "$staging_dir/speakerkit-coreml-v1"
else
  whisper_revision="0b364b566045a405be7225ee1e415a073e04da77"
  pomni_revision="3b4240718b502a7353aa54b6e8b981951b6e8396"
  speakerkit_revision="86ec9c929b52208b6656eb6a6361ed0d822a1f78"

  download \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/$whisper_revision/ggml-large-v3-turbo-q5_0.bin" \
    "$staging_dir/ggml-large-v3-turbo-q5_0.bin"
  download \
    "https://huggingface.co/Pomni/whisper-large-v3-turbo-ggml-allquants/resolve/$pomni_revision/ggml-large-v3-turbo-q5_1.bin" \
    "$staging_dir/ggml-large-v3-turbo-q5_1.bin"
  download \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/$whisper_revision/ggml-large-v3-turbo-q8_0.bin" \
    "$staging_dir/ggml-large-v3-turbo-q8_0.bin"
  download \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/$whisper_revision/ggml-large-v3-turbo-encoder.mlmodelc.zip" \
    "$work_dir/upstream-encoder.zip"
  ditto -x -k "$work_dir/upstream-encoder.zip" "$staging_dir"

  speakerkit_paths=(
    speaker_segmenter/pyannote-v3/W8A16/README.txt
    speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/analytics/coremldata.bin
    speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/coremldata.bin
    speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/metadata.json
    speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/model.mil
    speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/weights/weight.bin
    speaker_embedder/pyannote-v3/W8A16/README.txt
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/analytics/coremldata.bin
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/coremldata.bin
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/metadata.json
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/model.mil
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/weights/weight.bin
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/analytics/coremldata.bin
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/coremldata.bin
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/metadata.json
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/model.mil
    speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/weights/weight.bin
    speaker_clusterer/pyannote-v4/W32A32/README.txt
    speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/analytics/coremldata.bin
    speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/coremldata.bin
    speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/metadata.json
    speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/model.mil
    speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/weights/weight.bin
  )

  for relative_path in "${speakerkit_paths[@]}"; do
    download \
      "https://huggingface.co/argmaxinc/speakerkit-coreml/resolve/$speakerkit_revision/$relative_path" \
      "$staging_dir/speakerkit-coreml-v1/$relative_path"
  done
fi

COPYFILE_DISABLE=1 ditto --norsrc \
  "$repo_root/Docs/model-assets/THIRD_PARTY_NOTICES.md" \
  "$staging_dir/speakerkit-coreml-v1/THIRD_PARTY_NOTICES.md"

find "$staging_dir/ggml-large-v3-turbo-encoder.mlmodelc" \
  "$staging_dir/speakerkit-coreml-v1" -exec touch -t 202601010000 {} +

for model_name in \
  ggml-large-v3-turbo-q5_0.bin \
  ggml-large-v3-turbo-q5_1.bin \
  ggml-large-v3-turbo-q8_0.bin; do
  COPYFILE_DISABLE=1 ditto --norsrc "$staging_dir/$model_name" "$output_dir/$model_name"
done

(
  cd "$staging_dir"
  find ggml-large-v3-turbo-encoder.mlmodelc -print \
    | LC_ALL=C sort \
    | zip -X -9 "$output_dir/ggml-large-v3-turbo-encoder.mlmodelc.zip" -@ >/dev/null
  find speakerkit-coreml-v1 -print \
    | LC_ALL=C sort \
    | zip -X -9 "$output_dir/speakerkit-coreml-v1.zip" -@ >/dev/null
)

COPYFILE_DISABLE=1 ditto --norsrc \
  "$repo_root/Docs/model-assets/THIRD_PARTY_NOTICES.md" \
  "$output_dir/THIRD_PARTY_NOTICES.md"
COPYFILE_DISABLE=1 ditto --norsrc \
  "$repo_root/scripts/model-assets-v1.sha256" \
  "$output_dir/model-assets-v1.sha256"

(
  cd "$output_dir"
  shasum -a 256 -c model-assets-v1.sha256
)

printf 'Prepared verified model assets in %s\n' "$output_dir"
