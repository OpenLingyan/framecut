#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
SOURCE_ICON="${PROJECT_ROOT}/Resources/FrameCut.png"
ICONSET_DIR="${PROJECT_ROOT}/.build/FrameCut.iconset"
OUTPUT_ICON="${PROJECT_ROOT}/Resources/FrameCut.icns"

if [[ ! -f "${SOURCE_ICON}" ]]; then
    echo "Missing icon source: ${SOURCE_ICON}" >&2
    exit 1
fi

mkdir -p "${ICONSET_DIR}"

make_icon() {
    local size="$1"
    local filename="$2"
    sips -z "${size}" "${size}" "${SOURCE_ICON}" \
        --out "${ICONSET_DIR}/${filename}" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil --convert icns "${ICONSET_DIR}" --output "${OUTPUT_ICON}"
echo "Built ${OUTPUT_ICON}"
