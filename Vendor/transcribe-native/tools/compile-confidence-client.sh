#!/bin/sh
set -eu
framework=$1
output=$2
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
clang -std=c11 -O2 -UNDEBUG -mmacosx-version-min=15.0 -I "$framework/Headers" \
  "$recipe_dir/tests/confidence-client.c" "$framework/Versions/A/VoicePenGigaAM" \
  -Wl,-rpath,"$(dirname "$framework")" -o "$output"
