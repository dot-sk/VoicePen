#!/bin/sh
set -eu
source_dir=$1
build_dir=$2
output=$3
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
clang -std=c11 -O2 -mmacosx-version-min=15.0 -I "$source_dir/include" -c "$recipe_dir/tests/client.c" -o "$output.o"
clang++ -mmacosx-version-min=15.0 "$output.o" "$build_dir/src/libtranscribe.a" "$build_dir/ggml/src/libggml.a" "$build_dir/ggml/src/libggml-base.a" "$build_dir/ggml/src/libggml-cpu.a" "$build_dir/ggml/src/ggml-metal/libggml-metal.a" -framework Accelerate -framework Foundation -framework Metal -framework MetalKit -o "$output"
