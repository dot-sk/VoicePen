#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/generate-appcast.sh <archive-zip> <download-url> <output-appcast>

Environment:
  SPARKLE_PRIVATE_KEY    Sparkle EdDSA private key exported from generate_keys.
  SPARKLE_SIGN_UPDATE    Optional path to Sparkle's sign_update tool.
  DERIVED_DATA           Optional DerivedData path used to discover sign_update.

The script signs the archive with Sparkle's sign_update tool and writes a
single-item appcast suitable for publishing through GitHub Pages.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

archive_path="${1:-}"
download_url="${2:-}"
output_path="${3:-}"

if [[ -z "$archive_path" || -z "$download_url" || -z "$output_path" ]]; then
  usage
  exit 64
fi

if [[ ! -f "$archive_path" ]]; then
  echo "Archive not found: $archive_path" >&2
  exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY is required to sign the update archive." >&2
  exit 1
fi

find_sign_update() {
  if [[ -n "${SPARKLE_SIGN_UPDATE:-}" ]]; then
    printf "%s\n" "$SPARKLE_SIGN_UPDATE"
    return
  fi

  local derived_data="${DERIVED_DATA:-/private/tmp/VoicePenDerivedData}"
  find "$derived_data/SourcePackages/artifacts" -path "*/Sparkle/bin/sign_update" -type f -print -quit 2>/dev/null
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print $key" "$app_info_plist"
}

sign_update_path="$(find_sign_update)"
if [[ -z "$sign_update_path" || ! -x "$sign_update_path" ]]; then
  echo "Sparkle sign_update tool was not found. Run make resolve-packages first." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

ditto -x -k "$archive_path" "$work_dir"
app_path="$(find "$work_dir" -maxdepth 2 -name "VoicePen.app" -type d -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "Archive does not contain VoicePen.app." >&2
  exit 1
fi

app_info_plist="$app_path/Contents/Info.plist"
short_version="$(plist_value "CFBundleShortVersionString")"
build_version="$(plist_value "CFBundleVersion")"
pub_date="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S %z")"
signature_fragment="$(printf "%s" "$SPARKLE_PRIVATE_KEY" | "$sign_update_path" --ed-key-file - "$archive_path")"

if [[ "$signature_fragment" != *"sparkle:edSignature="* || "$signature_fragment" != *"length="* ]]; then
  echo "sign_update did not return Sparkle signature metadata." >&2
  exit 1
fi

escaped_download_url="$(printf "%s" "$download_url" | xml_escape)"
escaped_short_version="$(printf "%s" "$short_version" | xml_escape)"
escaped_build_version="$(printf "%s" "$build_version" | xml_escape)"

mkdir -p "$(dirname "$output_path")"
cat >"$output_path" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>VoicePen Updates</title>
    <link>https://github.com/dot-sk/VoicePen/releases</link>
    <description>VoicePen macOS updates</description>
    <language>en</language>
    <item>
      <title>VoicePen ${escaped_short_version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${escaped_build_version}</sparkle:version>
      <sparkle:shortVersionString>${escaped_short_version}</sparkle:shortVersionString>
      <enclosure
        url="${escaped_download_url}"
        sparkle:version="${escaped_build_version}"
        sparkle:shortVersionString="${escaped_short_version}"
        ${signature_fragment}
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
APPCAST

printf "Created %s\n" "$output_path"
