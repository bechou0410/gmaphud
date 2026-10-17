#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
core_dir="$source_dir/core"
build_dir=$(mktemp -d /tmp/ythud-build.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cp -R "$source_dir/tweak/." "$build_dir/"
for name in avplayer-trial mini-player-layout stream-video-policy dedicated-output paused-frame playback-state dedicated-dashboard; do
    cp "$core_dir/$name.m" "$build_dir/"
done
for name in runtime-mode output-channel mini-player-layout stream-video-policy dedicated-output paused-frame playback-state; do
    cp "$core_dir/$name.h" "$build_dir/"
done
chmod 755 "$build_dir/layout/DEBIAN/postinst"
make -C "$build_dir" THEOS="${THEOS:-$HOME/theos}" FINALPACKAGE=1 package
mkdir -p "$source_dir/packages"
cp "$build_dir"/packages/*.deb "$source_dir/packages/"
