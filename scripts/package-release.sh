#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/FrameCut.app"
EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/FrameCut"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"

cd "${PROJECT_ROOT}"
"${SCRIPT_DIR}/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
ARCHITECTURES="$(lipo -archs "${EXECUTABLE}")"

if [[ " ${ARCHITECTURES} " == *" arm64 "* && " ${ARCHITECTURES} " == *" x86_64 "* ]]; then
    ARCHITECTURE_LABEL="universal2"
elif [[ " ${ARCHITECTURES} " == *" arm64 "* ]]; then
    ARCHITECTURE_LABEL="arm64"
elif [[ " ${ARCHITECTURES} " == *" x86_64 "* ]]; then
    ARCHITECTURE_LABEL="x86_64"
else
    echo "Unable to identify a supported release architecture: ${ARCHITECTURES}" >&2
    exit 1
fi

SIGNATURE_DETAILS="$(codesign -dvvv "${APP_BUNDLE}" 2>&1 || true)"
if [[ "${SIGNATURE_DETAILS}" == *"Authority=Developer ID Application:"* ]]; then
    SIGNATURE_LABEL="developer-id-signed"
else
    SIGNATURE_LABEL="unsigned"
fi

ARCHIVE_NAME="FrameCut-${VERSION}-macOS-${ARCHITECTURE_LABEL}-${SIGNATURE_LABEL}.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${DIST_DIR}/${CHECKSUM_NAME}"

rm -f -- "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ARCHIVE_PATH}"

(
    cd "${DIST_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > "${CHECKSUM_NAME}"
    shasum -a 256 -c "${CHECKSUM_NAME}"
)

echo "Release archive: ${ARCHIVE_PATH}"
echo "SHA-256 file:  ${CHECKSUM_PATH}"
