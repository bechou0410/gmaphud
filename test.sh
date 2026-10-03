#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_dir=$(mktemp -d /tmp/gmaphud-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" -I"$source_dir/provider" \
  "$source_dir/common/speed-state.m" "$source_dir/provider/nav-source.m" \
  "$source_dir/provider/nav-payload.m" "$source_dir/tests/speed-state-tests.m" \
  -o "$test_dir/speed-state"
"$test_dir/speed-state"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" "$source_dir/common/test-state.m" \
  "$source_dir/tests/test-state-tests.m" -o "$test_dir/test-state"
"$test_dir/test-state"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" "$source_dir/common/speed-presentation.m" \
  "$source_dir/tests/speed-presentation-tests.m" -o "$test_dir/presentation"
"$test_dir/presentation"
