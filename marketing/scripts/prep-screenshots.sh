#!/usr/bin/env bash
# Prepare iOS App Store screenshots:
#   - flattens alpha channel (App Store rejects PNGs with alpha)
#   - resizes/pads to the iPhone 6.9" required size 1320x2868
#
# Usage:
#   ./prep-screenshots.sh <input-folder> [output-folder]
# Defaults: output to ../screenshots/iphone-6.9
#
# Requirements: ffmpeg, sips
set -euo pipefail

INPUT_DIR="${1:?Pass a folder of source PNG screenshots}"
OUTPUT_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/screenshots/iphone-6.9}"

mkdir -p "$OUTPUT_DIR"

count=0
for src in "$INPUT_DIR"/*.png "$INPUT_DIR"/*.PNG; do
  [ -e "$src" ] || continue
  count=$((count + 1))
  name=$(basename "$src")
  out="$OUTPUT_DIR/$name"
  ffmpeg -y -loglevel error -i "$src" \
    -vf "scale=1320:2868:force_original_aspect_ratio=decrease,pad=1320:2868:(ow-iw)/2:(oh-ih)/2:color=0x0F1730,format=rgb24" \
    "$out"
  printf "  ✓ %s → %s\n" "$name" "$out"
done

if [ "$count" -eq 0 ]; then
  echo "No PNGs found in $INPUT_DIR" >&2
  exit 1
fi

echo "Done. $count screenshot(s) written to $OUTPUT_DIR (1320×2868, no alpha)."
