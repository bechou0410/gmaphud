#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${GMAPHUD_CHECK_RUNNING:-0}" != 1 ] && [ "${GMAPHUD_CHECK_RAW:-0}" != 1 ]; then
  exec python3 "$source_dir/gmaphud-check.py" build "$@"
fi
scheme=${1:-all}
case "$scheme" in
  all) sh "$0" rootless; sh "$0" rootful; exit ;;
  rootless) package_scheme=rootless ;;
  rootful) package_scheme= ;;
  *) echo "Usage: $0 [all|rootless|rootful]" >&2; exit 1 ;;
esac
build_dir=$(mktemp -d /tmp/gmaphud-build.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cp -R "$source_dir/tweak/." "$build_dir/"
cp "$source_dir"/common/alert-state.[mh] "$source_dir"/common/speed-state.[mh] "$source_dir"/common/test-state.[mh] "$source_dir"/common/speed-presentation.[mh] "$build_dir/"
cp "$source_dir"/common/diagnostics.[mh] "$build_dir/"
cp "$source_dir"/common/source-output.[mh] "$source_dir"/common/source-transport.[mh] "$build_dir/"
cp "$source_dir/provider/gofa-payload.swift" "$build_dir/"
cp "$source_dir"/provider/vietmap-output.[mh] "$source_dir"/provider/waze-output.[mh] "$source_dir"/provider/waze-limit-search.[ch] "$build_dir/"
cp "$source_dir"/common/placement-state.[mh] "$source_dir"/common/guidance-state.[mh] "$build_dir/"
cp "$source_dir/provider/vietmap-source.x" "$build_dir/vietmap-source.x"
cp "$source_dir/provider/"background-location.[mh] "$build_dir/"
cp "$source_dir/provider/"nav-source.[mh] "$source_dir/provider/"nav-payload.[mh] "$source_dir/provider/"vietmap-alert-assets.[mh] "$build_dir/"
notice_dir="$build_dir/layout/usr/share/doc/com.chou.googlemaps.vietmap"
mkdir -p "$notice_dir"
cp "$source_dir/LICENSE" "$notice_dir/LICENSE"
cp "$source_dir/DISCLAIMER.md" "$notice_dir/DISCLAIMER"
make -C "$build_dir" THEOS="${THEOS:-$HOME/theos}" THEOS_PACKAGE_SCHEME="$package_scheme" FINALPACKAGE=1 package
mkdir -p "$source_dir/packages"
cp "$build_dir"/packages/*.deb "$source_dir/packages/"
