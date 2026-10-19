#!/bin/sh
# Runs the host tests for the scale math on the Mac.
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/carplay-scale-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
clang -fobjc-arc -Wall -Wextra -Werror -I "$source_dir/common" "$source_dir/common/scale-math.m" "$source_dir/tests/scale-math-tests.m" -framework Foundation -o "$build_dir/scale-math-tests"
"$build_dir/scale-math-tests"
