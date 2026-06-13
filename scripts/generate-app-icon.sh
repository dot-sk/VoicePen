#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ICON_DIR="$ROOT_DIR/VoicePen/Assets.xcassets/AppIcon.appiconset"
MASTER_ICON="${TMPDIR:-/tmp}/voicepen-parametric-appicon-1024.png"

command -v magick >/dev/null 2>&1 || {
  printf "ImageMagick is required. Install it with: brew install imagemagick\n" >&2
  exit 127
}

BLUE="#4763F2"
PURPLE="#806BEB"
CANVAS_SIZE=1024
ICON_INSET=92
ICON_MAX=932
CORNER_RADIUS=210

MIC_LEFT=432
MIC_TOP=248
MIC_RIGHT=592
MIC_BOTTOM=612
MIC_RADIUS=80
STROKE_WIDTH=44

magick \
  \( -size "${CANVAS_SIZE}x${CANVAS_SIZE}" xc: \
    -sparse-color barycentric "0,0 $BLUE $CANVAS_SIZE,$CANVAS_SIZE $PURPLE" \) \
  \( -size "${CANVAS_SIZE}x${CANVAS_SIZE}" xc:none \
    -fill white \
    -draw "roundrectangle $ICON_INSET,$ICON_INSET $ICON_MAX,$ICON_MAX $CORNER_RADIUS,$CORNER_RADIUS" \
    -alpha extract \) \
  -alpha off \
  -compose CopyOpacity \
  -composite \
  -fill none \
  -stroke white \
  -strokewidth "$STROKE_WIDTH" \
  -draw "stroke-linecap round path 'M 344,448 C 344,604 454,696 512,696 C 570,696 680,604 680,448'" \
  -fill white \
  -stroke none \
  -draw "roundrectangle $MIC_LEFT,$MIC_TOP $MIC_RIGHT,$MIC_BOTTOM $MIC_RADIUS,$MIC_RADIUS" \
  -fill none \
  -stroke white \
  -strokewidth "$STROKE_WIDTH" \
  -draw "stroke-linecap round line 512,696 512,792 line 430,792 594,792" \
  "$MASTER_ICON"

magick "$MASTER_ICON" -resize 16x16 "$APP_ICON_DIR/icon_16x16.png"
magick "$MASTER_ICON" -resize 32x32 "$APP_ICON_DIR/icon_16x16@2x.png"
magick "$MASTER_ICON" -resize 32x32 "$APP_ICON_DIR/icon_32x32.png"
magick "$MASTER_ICON" -resize 64x64 "$APP_ICON_DIR/icon_32x32@2x.png"
magick "$MASTER_ICON" -resize 128x128 "$APP_ICON_DIR/icon_128x128.png"
magick "$MASTER_ICON" -resize 256x256 "$APP_ICON_DIR/icon_128x128@2x.png"
magick "$MASTER_ICON" -resize 256x256 "$APP_ICON_DIR/icon_256x256.png"
magick "$MASTER_ICON" -resize 512x512 "$APP_ICON_DIR/icon_256x256@2x.png"
magick "$MASTER_ICON" -resize 512x512 "$APP_ICON_DIR/icon_512x512.png"
magick "$MASTER_ICON" -resize 1024x1024 "$APP_ICON_DIR/icon_512x512@2x.png"

printf "Generated AppIcon PNGs in %s\n" "$APP_ICON_DIR"
