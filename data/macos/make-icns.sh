#!/bin/sh
# Usage: make-icns.sh <input.svg> <output.icns> <rsvg-convert>
set -e

SVG="$1"
OUTPUT="$2"
RSVG_CONVERT="$3"

WORK_DIR="$(mktemp -d)"
ICONSET="$WORK_DIR/BlackBox.iconset"
mkdir "$ICONSET"

render() {
    "$RSVG_CONVERT" -w "$1" -h "$1" "$SVG" -o "$ICONSET/$2"
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$WORK_DIR"
