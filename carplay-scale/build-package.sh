#!/bin/sh
# Runs the host tests, then builds the rootless package into carplay-scale/packages/.
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$source_dir/test.sh"
build_dir=$(mktemp -d /tmp/carplay-scale-build.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cp -R "$source_dir/tweak/." "$build_dir/"
cp "$source_dir"/common/*.[mh] "$build_dir/"
chmod 755 "$build_dir/layout/DEBIAN/postinst" "$build_dir/layout/DEBIAN/postrm"
make -C "$build_dir" THEOS="${THEOS:-$HOME/theos}" FINALPACKAGE=1 package
mkdir -p "$source_dir/packages"
cp "$build_dir"/packages/*.deb "$source_dir/packages/"
