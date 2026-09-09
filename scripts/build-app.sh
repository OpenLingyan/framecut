#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_BUNDLE="${PROJECT_ROOT}/dist/FrameCut.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"

cd "${PROJECT_ROOT}"

if [[ -f "${PROJECT_ROOT}/Resources/FrameCut.png" ]]; then
    "${SCRIPT_DIR}/build-icon.sh"
fi

swift build -c release

if [[ -e "${APP_BUNDLE}" ]]; then
    rm -rf "${APP_BUNDLE}"
fi

mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${PROJECT_ROOT}/.build/release/FrameCut" "${CONTENTS_DIR}/MacOS/FrameCut"
cp "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod +x "${CONTENTS_DIR}/MacOS/FrameCut"

if [[ -f "${PROJECT_ROOT}/Resources/FrameCut.icns" ]]; then
    cp "${PROJECT_ROOT}/Resources/FrameCut.icns" "${CONTENTS_DIR}/Resources/FrameCut.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string FrameCut" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile FrameCut" "${CONTENTS_DIR}/Info.plist"
fi

codesign --force --deep --sign - "${APP_BUNDLE}"
echo "Built ${APP_BUNDLE}"
