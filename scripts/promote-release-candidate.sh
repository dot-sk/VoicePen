#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/promote-release-candidate.sh <candidate-zip> <output-zip> <version> <build> <codesign-identity>
USAGE
}

candidate_zip="${1:-}"
output_zip="${2:-}"
expected_version="${3:-}"
expected_build="${4:-}"
codesign_identity="${5:-}"

if [[ -z "$candidate_zip" || -z "$output_zip" || -z "$expected_version" || -z "$expected_build" || -z "$codesign_identity" ]]; then
  usage >&2
  exit 64
fi

if [[ ! -f "$candidate_zip" ]]; then
  echo "Release candidate does not exist: $candidate_zip" >&2
  exit 1
fi

if [[ ! "$expected_build" =~ ^[0-9]+$ ]]; then
  echo "Expected build number must be numeric: $expected_build" >&2
  exit 64
fi

work_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/voicepen-release-promotion.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

ditto -x -k "$candidate_zip" "$work_dir"

app="$work_dir/VoicePen.app"
info_plist="$app/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  echo "Release candidate does not contain VoicePen.app/Contents/Info.plist." >&2
  exit 1
fi

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"

if [[ "$actual_version" != "$expected_version" ]]; then
  echo "Release candidate version is $actual_version, expected $expected_version." >&2
  exit 1
fi

if [[ "$actual_build" != "$expected_build" ]]; then
  echo "Release candidate build is $actual_build, expected $expected_build." >&2
  exit 1
fi

codesign --verify --strict --deep --verbose=2 "$app"
codesign --force --deep --strict --sign "$codesign_identity" "$app"
codesign --verify --strict --deep --verbose=2 "$app"

mkdir -p "$(dirname "$output_zip")"
rm -f "$output_zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_zip"

printf "Promoted %s (%s) to %s\n" "$actual_version" "$actual_build" "$output_zip"
