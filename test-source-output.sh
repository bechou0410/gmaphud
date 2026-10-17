#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${GMAPHUD_CHECK_RUNNING:-0}" != 1 ] && [ "${GMAPHUD_CHECK_RAW:-0}" != 1 ]; then
  exec python3 "$source_dir/gmaphud-check.py" source-test "$@"
fi
test_dir=$(mktemp -d /tmp/gmaphud-output-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" -I"$source_dir/provider" \
  "$source_dir/common/source-output.m" "$source_dir/common/speed-state.m" \
  "$source_dir/common/alert-state.m" "$source_dir/provider/vietmap-output.m" \
  "$source_dir/provider/vietmap-alert-assets.m" "$source_dir/provider/nav-source.m" \
  "$source_dir/provider/nav-payload.m" "$source_dir/tests/source-output-tests.m" \
  -o "$test_dir/source-output"
"$test_dir/source-output" "$source_dir/tweak/layout/usr/share/gmaphud/gmaphud"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  "-DGVM_OUTPUT_NAMESPACE=\"com.chou.gmaphud.tests.output.$$\"" \
  -I"$source_dir/common" "$source_dir/common/source-output.m" \
  "$source_dir/common/source-transport.m" "$source_dir/common/speed-state.m" \
  "$source_dir/common/alert-state.m" "$source_dir/tests/source-transport-tests.m" \
  -o "$test_dir/source-transport"
"$test_dir/source-transport"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" -I"$source_dir/provider" \
  "$source_dir/common/source-output.m" "$source_dir/common/speed-state.m" \
  "$source_dir/common/alert-state.m" "$source_dir/provider/waze-output.m" \
  "$source_dir/tests/waze-output-tests.m" -o "$test_dir/waze-output"
"$test_dir/waze-output"
xcrun clang -Wall -Wextra -Werror "$source_dir/tests/gofa-alert-policy-tests.c" -o "$test_dir/gofa-alert-policy"
"$test_dir/gofa-alert-policy"
xcrun clang -Wall -Wextra -Werror -I"$source_dir/provider" "$source_dir/provider/waze-limit-search.c" \
  "$source_dir/tests/waze-limit-search-tests.c" -o "$test_dir/waze-limit-search"
"$test_dir/waze-limit-search"
