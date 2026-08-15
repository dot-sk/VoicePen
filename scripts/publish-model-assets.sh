#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assets_dir="${1:-}"
repository="${GITHUB_REPOSITORY:-dot-sk/VoicePen}"
tag="${MODEL_ASSETS_TAG:-model-assets-v1}"

if [[ -z "$assets_dir" ]]; then
  printf 'Usage: %s ASSETS_DIR\n' "$0" >&2
  exit 64
fi

assets_dir="$(cd "$assets_dir" && pwd)"
checksum_file="$assets_dir/model-assets-v1.sha256"
test -f "$checksum_file"

(
  cd "$assets_dir"
  shasum -a 256 -c model-assets-v1.sha256
)

asset_names=(
  ggml-large-v3-turbo-q5_0.bin
  ggml-large-v3-turbo-q5_1.bin
  ggml-large-v3-turbo-q8_0.bin
  ggml-large-v3-turbo-encoder.mlmodelc.zip
  speakerkit-coreml-v1.zip
  THIRD_PARTY_NOTICES.md
  model-assets-v1.sha256
)

if ! gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  gh release create "$tag" \
    --repo "$repository" \
    --draft \
    --title "VoicePen model assets v1" \
    --notes-file "$repo_root/Docs/model-assets/THIRD_PARTY_NOTICES.md"
fi

release_json="$(gh release view "$tag" --repo "$repository" --json isDraft,assets)"
if [[ "$(jq -r '.isDraft' <<<"$release_json")" != "true" ]]; then
  printf 'Release %s is already published and immutable.\n' "$tag" >&2
  exit 73
fi

for asset_name in "${asset_names[@]}"; do
  asset_path="$assets_dir/$asset_name"
  test -f "$asset_path"
  local_size="$(stat -f '%z' "$asset_path")"
  remote_size="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .size' <<<"$release_json")"
  if [[ -n "$remote_size" ]]; then
    if [[ "$remote_size" != "$local_size" ]]; then
      printf 'Draft release contains %s with unexpected size %s.\n' "$asset_name" "$remote_size" >&2
      exit 65
    fi
    continue
  fi

  gh release upload "$tag" "$asset_path" --repo "$repository"
  release_json="$(gh release view "$tag" --repo "$repository" --json isDraft,assets)"
done

for asset_name in "${asset_names[@]}"; do
  local_size="$(stat -f '%z' "$assets_dir/$asset_name")"
  remote_size="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .size' <<<"$release_json")"
  if [[ "$remote_size" != "$local_size" ]]; then
    printf 'Remote verification failed for %s.\n' "$asset_name" >&2
    exit 65
  fi
done

gh release edit "$tag" --repo "$repository" --draft=false
gh release view "$tag" --repo "$repository" --json url,tagName,isDraft,assets

if [[ "${VERIFY_MODEL_ASSET_DOWNLOADS:-1}" == "1" ]]; then
  verify_dir="$(mktemp -d /private/tmp/voicepen-model-assets-verify.XXXXXX)"
  trap 'rm -rf "$verify_dir"' EXIT
  gh release download "$tag" --repo "$repository" --dir "$verify_dir"
  (
    cd "$verify_dir"
    shasum -a 256 -c model-assets-v1.sha256
  )
fi
