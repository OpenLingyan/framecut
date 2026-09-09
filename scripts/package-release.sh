#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/FrameCut.app"
EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/FrameCut"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
DMG_TOOLS_DIR="${PROJECT_ROOT}/.build/dmg-tools"

# These small, hash-pinned tools run only on the build machine, never in the app.
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "DMG packaging requires Python 3.10 or later.")'
if [[ ! -x "${DMG_TOOLS_DIR}/bin/python" ]]; then
    python3 -m venv "${DMG_TOOLS_DIR}"
fi
"${DMG_TOOLS_DIR}/bin/python" -m pip install --disable-pip-version-check \
    --only-binary=:all: --require-hashes -r "${SCRIPT_DIR}/dmg-requirements.txt"

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

RELEASE_NAME="FrameCut-${VERSION}-macOS-${ARCHITECTURE_LABEL}-${SIGNATURE_LABEL}"
STAGING_DIR="$(mktemp -d "${DIST_DIR}/.release-XXXXXX")"
trap 'rm -rf -- "${STAGING_DIR}"' EXIT

swift "${SCRIPT_DIR}/render-dmg-background.swift" "${STAGING_DIR}"
"${DMG_TOOLS_DIR}/bin/dmgbuild" -s "${SCRIPT_DIR}/dmg-settings.py" \
    -D "app=${APP_BUNDLE}" \
    -D "icon=${APP_BUNDLE}/Contents/Resources/FrameCut.icns" \
    -D "background=${STAGING_DIR}/installer.png" \
    "FrameCut ${VERSION}" "${STAGING_DIR}/${RELEASE_NAME}.dmg"
"${DMG_TOOLS_DIR}/bin/python" "${SCRIPT_DIR}/verify-dmg.py" \
    "${STAGING_DIR}/${RELEASE_NAME}.dmg" "${VERSION}" "${ARCHITECTURE_LABEL}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${STAGING_DIR}/${RELEASE_NAME}.zip"

for extension in dmg zip; do
    (
        cd "${STAGING_DIR}"
        shasum -a 256 "${RELEASE_NAME}.${extension}" > "${RELEASE_NAME}.${extension}.sha256"
        shasum -a 256 -c "${RELEASE_NAME}.${extension}.sha256"
    )
    mv -f -- "${STAGING_DIR}/${RELEASE_NAME}.${extension}" "${DIST_DIR}/"
    mv -f -- "${STAGING_DIR}/${RELEASE_NAME}.${extension}.sha256" "${DIST_DIR}/"
    echo "Release artifact: ${DIST_DIR}/${RELEASE_NAME}.${extension}"
    echo "SHA-256 file:     ${DIST_DIR}/${RELEASE_NAME}.${extension}.sha256"
done
