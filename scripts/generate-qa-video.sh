#!/bin/zsh

set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: $0 /absolute/or/relative/path/qa-sample.mp4"
    exit 64
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    print -u2 "FFmpeg is required. Install it with: brew install ffmpeg"
    exit 69
fi

output_path="$1"
output_directory="${output_path:h}"
mkdir -p "$output_directory"

ffmpeg \
    -y \
    -hide_banner \
    -loglevel error \
    -f lavfi \
    -i "testsrc2=size=1280x720:rate=30" \
    -f lavfi \
    -i "sine=frequency=880:sample_rate=48000" \
    -t 12 \
    -map 0:v:0 \
    -map 1:a:0 \
    -c:v libx264 \
    -preset veryfast \
    -crf 18 \
    -pix_fmt yuv420p \
    -g 60 \
    -keyint_min 60 \
    -sc_threshold 0 \
    -c:a aac \
    -b:a 128k \
    -movflags +faststart \
    "$output_path"

print -r -- "Generated synthetic QA video: $output_path"
