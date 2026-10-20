#!/usr/bin/env bash
set -euo pipefail
model="${1:?Usage: prepare-gigaam-model-assets.sh MODEL_GGUF OUTPUT_DIR PACKAGE_DIR}"
output="${2:?OUTPUT_DIR is required}"
package="${3:?PACKAGE_DIR is required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${4:-}" ]]; then
  printf 'Prepare offline inputs only; use publisher --verify-only to emit a verified download URL.\n' >&2
  exit 64
fi
digest="06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae"
[[ "$(stat -f %z "$model")" == 1172222176 ]]
[[ "$(shasum -a 256 "$model" | awk '{print $1}')" == "$digest" ]]
[[ "$(jq -r .model.gguf_sha256 "$package/manifest.json")" == "$digest" ]]
mkdir -p "$output"
[[ ! -e "$output/gigaam-600m-F16.gguf" ]] || { printf 'Refusing to overwrite model asset\n' >&2; exit 73; }
cp -c "$model" "$output/gigaam-600m-F16.gguf"
ditto "$package/licenses" "$output/licenses"
cp "$package/manifest.json" "$output/native-package-manifest.json"
printf '%s  gigaam-600m-F16.gguf\n' "$digest" > "$output/gigaam-model-assets.sha256"
jq -n --arg package "$(jq -r .candidate "$package/manifest.json")" --arg sha "$digest" '{id:"gigaam-multilingual-600m-f16",displayName:"GigaAM Multilingual 600M F16",version:"multilingual-600m-f16-stock25-v1",sizeLabel:"1.17 GB",sourceRepo:"ai-sage/GigaAM-Multilingual",sourceKind:"GigaAM transcribe.cpp GGUF",backend:"gigaAM",isQuantized:false,supportedLanguageCodes:["ru","en","kk","ky","uz"],description:"Automatic multilingual recognition with greedy CTC. Text only; requires Apple Silicon and Metal.",downloadURL:null,artifactFileName:"gigaam-600m-F16.gguf",byteSize:1172222176,sha256:$sha,capabilities:{timestamps:false},companionArtifacts:[],runtimePackageID:$package}' > "$output/model-manifest-entry.json"
printf 'Prepared local publication inputs at %s. No asset was published.\n' "$output"
uv --native-tls run --no-project --python 3.13 python "$repo_root/Tools/GigaAMIntegration/prepare_publication.py" "$output"
