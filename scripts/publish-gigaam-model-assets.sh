#!/usr/bin/env bash
set -euo pipefail
assets="${1:?Usage: publish-model-assets.sh --gigaam ASSETS_DIR [--dry-run|--publish|--verify-only]}"
mode="${2:---dry-run}"
case "$mode" in --dry-run|--publish|--verify-only) ;; *) printf 'Unknown mode\n' >&2; exit 64;; esac
assets="$(cd "$assets" && pwd)"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plan="$assets/gigaam-publication-plan.json"
jq -e '.schemaVersion == 1 and .publicationState == "not-published" and (.repository | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and (.tag | test("^model-assets-gigaam-600m-f16-v[1-9][0-9]*$")) and (.targetCommit | test("^[0-9a-f]{40}$")) and ([.assets[].name] == ["gigaam-600m-F16.gguf", "gigaam-600m-F16-notices.zip"]) and .assets[0].byteSize == 1172222176 and .assets[0].sha256 == "06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae"' "$plan" >/dev/null
repository="$(jq -r .repository "$plan")"
jq -e '.assets[1].byteSize == 13262 and .assets[1].sha256 == "96fad5236215500ca3e14c9059a49ada7f62dcdc77b5f8329c4ce05e36e98710"' "$plan" >/dev/null
tag="$(jq -r .tag "$plan")"
commit="$(jq -r .targetCommit "$plan")"
jq -e '.id == "gigaam-multilingual-600m-f16" and .backend == "gigaAM" and .downloadURL == null and .artifactFileName == "gigaam-600m-F16.gguf" and .byteSize == 1172222176 and .sha256 == "06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae" and .runtimePackageID == "voicepen-gigaam-600m-0.1.0-candidate.2" and .capabilities.timestamps == false and .supportedLanguageCodes == ["ru","en","kk","ky","uz"]' "$assets/model-manifest-entry.json" >/dev/null
names=(gigaam-600m-F16.gguf gigaam-600m-F16-notices.zip)
for name in "${names[@]}"; do
  expected_size="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .byteSize' "$plan")"
  expected_sha="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .sha256' "$plan")"
  [[ "$(stat -f %z "$assets/$name")" == "$expected_size" ]]
  [[ "$(shasum -a 256 "$assets/$name" | awk '{print $1}')" == "$expected_sha" ]]
done
[[ "$(shasum -a 256 "$assets/native-package-manifest.json" | awk '{print $1}')" == "$(jq -r .nativePackageManifestSHA256 "$plan")" ]]
[[ "$(shasum -a 256 "$assets/model-manifest-entry.json" | awk '{print $1}')" == "$(jq -r .modelEntrySHA256 "$plan")" ]]
if [[ "$mode" == --dry-run ]]; then
  jq '. + {remoteChecked:false, action:"Create a new non-latest release; refuse any existing release; verify both public downloads before emitting the model entry"}' "$plan"
  exit 0
fi
work="$(mktemp -d /private/tmp/voicepen-gigaam-publish.XXXXXX)"
trap 'rm -rf "$work"' EXIT
exists=false
if gh api "repos/$repository/releases/tags/$tag" > "$work/release.json" 2> "$work/api-error"; then
  exists=true
elif ! rg -q 'HTTP 404' "$work/api-error"; then
  printf 'Cannot determine remote release state; refusing mutation.\n' >&2
  exit 69
else
  gh api --paginate --slurp "repos/$repository/releases?per_page=100" > "$work/release-pages.json"
  jq --arg tag "$tag" '[.[][] | select(.tag_name == $tag)]' "$work/release-pages.json" > "$work/matching-releases.json"
  count="$(jq length "$work/matching-releases.json")"
  if [[ "$count" == 1 ]]; then
    jq '.[0]' "$work/matching-releases.json" > "$work/release.json"
    exists=true
  elif [[ "$count" != 0 ]]; then
    printf 'Ambiguous remote release state; refusing mutation.\n' >&2
    exit 69
  fi
fi
if [[ "$mode" == --publish ]]; then
  if [[ "$exists" == true ]]; then
    printf 'Release %s already exists; no assets or release state will be replaced. Use --verify-only for a published release.\n' "$tag" >&2
    exit 73
  fi
  acceptance="${GIGAAM_MODEL_ACCEPTANCE_REPORT:-$repo_root/.local/asr-quality/native-gigaam-600m/host-local-acceptance.json}"
  jq -e '.schema_version == 1 and .model_artifact.accepted == true and .model_artifact.sha256 == "06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae" and .runtime_sha256 == "f2fe97a8a947483484d60c8af5e4179b26355387c2765cf83d62a7a83dbb3330" and .candidate_manifest_sha256 == "7738da1d56246941906071a4177dd5586dd02c5560df4d97eb6fee72b52626e8"' "$acceptance" >/dev/null
  if gh api "repos/$repository/git/ref/tags/$tag" > /dev/null 2> "$work/api-error"; then
    printf 'Tag %s already exists; refusing to reuse it.\n' "$tag" >&2
    exit 73
  elif ! rg -q 'HTTP 404' "$work/api-error"; then
    printf 'Cannot determine remote tag state; refusing mutation.\n' >&2
    exit 69
  fi
  gh api "repos/$repository/commits/$commit" --jq .sha | rg -qx "$commit"
  cat > "$work/notes.md" <<EOF
GigaAM Multilingual 600M F16 model assets for local VoicePen recognition.

The notices archive contains source and derived-model license texts, source cards,
checkpoint provenance, and the model SHA-256. This release contains model assets,
not a native framework or signed application release.

$(jq -r '.assets[] | "\(.sha256)  \(.name)"' "$plan")
EOF
  gh release create "$tag" --repo "$repository" --target "$commit" --draft --latest=false --title "GigaAM Multilingual 600M F16 model assets ($tag)" --notes-file "$work/notes.md"
  gh api --paginate --slurp "repos/$repository/releases?per_page=100" > "$work/release-pages.json"
  release_id="$(jq -er --arg tag "$tag" --arg commit "$commit" '[.[][] | select(.tag_name == $tag and .target_commitish == $commit and .draft == true)] | if length == 1 then .[0].id else error("Cannot identify the created draft") end' "$work/release-pages.json")"
  gh release upload "$tag" "$assets/${names[0]}" "$assets/${names[1]}" --repo "$repository"
  gh api "repos/$repository/releases/$release_id" > "$work/release.json"
  jq -e '.draft == true and (.assets | length == 2)' "$work/release.json" >/dev/null
  for name in "${names[@]}"; do
    size="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .byteSize' "$plan")"
    jq -e --arg name "$name" --argjson size "$size" '.assets[] | select(.name == $name) | .size == $size' "$work/release.json" >/dev/null
  done
  gh api --method PATCH "repos/$repository/releases/$release_id" -F draft=false -f make_latest=false > "$work/release.json"
elif [[ "$exists" != true ]]; then
  printf 'No published release exists to verify.\n' >&2
  exit 69
fi
jq -e '.draft == false and (.assets | length == 2)' "$work/release.json" >/dev/null
rm -f "$assets/verified-model-manifest-entry.json" "$assets/publication-receipt.json"
for name in "${names[@]}"; do
  url="https://github.com/$repository/releases/download/$tag/$name"
  size="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .byteSize' "$plan")"
  sha="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .sha256' "$plan")"
  jq -e --arg name "$name" --argjson size "$size" '.assets[] | select(.name == $name) | .size == $size' "$work/release.json" >/dev/null
  curl --fail --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --proto '=https' --proto-redir '=https' --output "$work/$name" "$url"
  [[ "$(stat -f %z "$work/$name")" == "$size" ]]
  [[ "$(shasum -a 256 "$work/$name" | awk '{print $1}')" == "$sha" ]]
done
url="https://github.com/$repository/releases/download/$tag/gigaam-600m-F16.gguf"
jq --arg url "$url" '.downloadURL=$url' "$assets/model-manifest-entry.json" > "$work/verified-model-manifest-entry.json"
jq -e --arg url "$url" '.id == "gigaam-multilingual-600m-f16" and .backend == "gigaAM" and .downloadURL == $url and .byteSize == 1172222176 and .sha256 == "06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae" and .capabilities.timestamps == false and .supportedLanguageCodes == ["ru","en","kk","ky","uz"]' "$work/verified-model-manifest-entry.json" >/dev/null
mv "$work/verified-model-manifest-entry.json" "$assets/verified-model-manifest-entry.json"
jq -n --arg repository "$repository" --arg tag "$tag" --arg url "$url" --argjson assets "$(jq .assets "$plan")" '{verified:true,repository:$repository,tag:$tag,modelURL:$url,assets:$assets}' > "$assets/publication-receipt.json"
printf 'Both public assets verified. Model entry: %s/verified-model-manifest-entry.json\n' "$assets"
