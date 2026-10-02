#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=$(mktemp -d /tmp/mapspeed-build.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cp -R "$source_dir/tweak/." "$build_dir/"
cp "$source_dir"/common/speed-state.[mh] "$source_dir"/common/test-state.[mh] "$source_dir"/common/speed-presentation.[mh] "$build_dir/"
cp "$source_dir/provider/vietmap-source.x" "$build_dir/vietmap-source.x"
cp "$source_dir/provider/"nav-source.[mh] "$source_dir/provider/"nav-payload.[mh] "$build_dir/"
notice_dir="$build_dir/layout/usr/share/doc/com.chou.googlemaps.vietmap"
mkdir -p "$notice_dir"
cp "$source_dir/LICENSE" "$notice_dir/LICENSE"
cp "$source_dir/DISCLAIMER.md" "$notice_dir/DISCLAIMER"
make -C "$build_dir" THEOS="${THEOS:-$HOME/theos}" FINALPACKAGE=1 package
mkdir -p "$source_dir/packages"
cp "$build_dir"/packages/*.deb "$source_dir/packages/"
