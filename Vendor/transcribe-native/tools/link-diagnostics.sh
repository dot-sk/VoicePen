#!/bin/sh
set -eu
build=$1
source_dir=$2
output=$3
clang++ -dynamiclib -mmacosx-version-min=15.0 \
  -Wl,-force_load,"$build/src/libtranscribe.a" \
  "$build/ggml/src/libggml.a" "$build/ggml/src/libggml-base.a" \
  "$build/ggml/src/libggml-cpu.a" "$build/ggml/src/ggml-metal/libggml-metal.a" \
  -framework Accelerate -framework Foundation -framework Metal -framework MetalKit \
  -Wl,-exported_symbols_list,"$source_dir/voicepen.exports" \
  -install_name @rpath/libvoicepen-gigaam-diagnostics.dylib -o "$output"
