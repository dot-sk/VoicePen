#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="${1:?Usage: prepare-gigaam-runtime.sh PACKAGE_ROOT [--allow-unaccepted-candidate]}"
package_root="$(cd "$package_root" && pwd)"
manifest="$package_root/manifest.json"
pin="$repo_root/Vendor/transcribe.spm/candidate-manifest.json"

if [[ "$(jq -r .acceptance "$manifest")" != accepted && "${2:-}" != --allow-unaccepted-candidate ]]; then
  printf 'Native package is unaccepted. Local evaluation requires --allow-unaccepted-candidate.\n' >&2
  exit 65
fi
cmp "$manifest" "$pin"
jq -e '.interface_version == "0.4.0" and .profile.window_policy == "stock25-v1" and .profile.weight_storage == "F16" and .profile.activations == "F32" and .profile.encoder == "Metal" and .target.architecture == "arm64"' "$manifest" >/dev/null
while IFS=$'\t' read -r relative digest; do
  case "$relative" in /*|*..*) printf 'Unsafe package path\n' >&2; exit 65;; esac
  actual="$(shasum -a 256 "$package_root/$relative" | awk '{print $1}')"
  [[ "$actual" == "$digest" ]] || { printf 'Package hash mismatch: %s\n' "$relative" >&2; exit 65; }
done < <(jq -r '.files | to_entries[] | [.key, .value] | @tsv' "$manifest")
while IFS=$'\t' read -r relative target; do
  [[ "$(readlink "$package_root/$relative")" == "$target" ]] || { printf 'Package symlink mismatch: %s\n' "$relative" >&2; exit 65; }
done < <(jq -r '(.symlinks // {}) | to_entries[] | [.key, .value] | @tsv' "$manifest")

destination="$repo_root/Vendor/transcribe.spm/Artifacts"
staging="$(mktemp -d "$repo_root/Vendor/transcribe.spm/.prepare.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$package_root/VoicePenGigaAM.xcframework" "$staging/VoicePenGigaAM.xcframework"
ditto "$package_root/licenses" "$staging/licenses"
cp "$manifest" "$staging/manifest.json"
mkdir -p "$destination"
rm -rf "$destination/VoicePenGigaAM.xcframework" "$destination/licenses"
mv "$staging/VoicePenGigaAM.xcframework" "$destination/VoicePenGigaAM.xcframework"
mv "$staging/licenses" "$destination/licenses"
mv "$staging/manifest.json" "$destination/manifest.json"
printf 'Prepared verified local GigaAM package: %s (%s)\n' "$(jq -r .candidate "$manifest")" "$(jq -r .acceptance "$manifest")"
