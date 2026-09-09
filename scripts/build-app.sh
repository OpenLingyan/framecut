#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_BUNDLE="${PROJECT_ROOT}/dist/FrameCut.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
BUILD_ARCHS_STRING="${FRAMECUT_BUILD_ARCHS:-arm64 x86_64}"
typeset -a BUILD_ARCHS
typeset -a SWIFT_BUILD_ARGUMENTS
BUILD_ARCHS=("${(@s: :)BUILD_ARCHS_STRING}")
SWIFT_BUILD_ARGUMENTS=(-c release)

if (( ${#BUILD_ARCHS[@]} == 0 )); then
    echo "FRAMECUT_BUILD_ARCHS must contain at least one architecture." >&2
    exit 1
fi

for architecture in "${BUILD_ARCHS[@]}"; do
    case "${architecture}" in
        arm64|x86_64)
            SWIFT_BUILD_ARGUMENTS+=(--arch "${architecture}")
            ;;
        *)
            echo "Unsupported architecture: ${architecture}" >&2
            echo "Supported values: arm64 x86_64" >&2
            exit 1
            ;;
    esac
done

cd "${PROJECT_ROOT}"

if [[ -f "${PROJECT_ROOT}/Resources/FrameCut.png" ]]; then
    "${SCRIPT_DIR}/build-icon.sh"
fi

swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BINARY_DIRECTORY="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
EXECUTABLE="${BINARY_DIRECTORY}/FrameCut"
LOCALIZATION_BUNDLE="${BINARY_DIRECTORY}/FrameCut_FrameCut.bundle"

if [[ ! -x "${EXECUTABLE}" ]]; then
    echo "Release executable was not produced at ${EXECUTABLE}." >&2
    exit 1
fi

if [[ ! -d "${LOCALIZATION_BUNDLE}" ]]; then
    echo "Localization resources were not produced at ${LOCALIZATION_BUNDLE}." >&2
    exit 1
fi

if [[ -e "${APP_BUNDLE}" ]]; then
    rm -rf "${APP_BUNDLE}"
fi

mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${EXECUTABLE}" "${CONTENTS_DIR}/MacOS/FrameCut"
cp "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod +x "${CONTENTS_DIR}/MacOS/FrameCut"
ditto "${LOCALIZATION_BUNDLE}" "${CONTENTS_DIR}/Resources/FrameCut_FrameCut.bundle"
for language in en zh-Hans; do
    ditto "${PROJECT_ROOT}/Resources/${language}.lproj" "${CONTENTS_DIR}/Resources/${language}.lproj"
done

if [[ -f "${PROJECT_ROOT}/Resources/FrameCut.icns" ]]; then
    cp "${PROJECT_ROOT}/Resources/FrameCut.icns" "${CONTENTS_DIR}/Resources/FrameCut.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string FrameCut" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile FrameCut" "${CONTENTS_DIR}/Info.plist"
fi

SIGNING_IDENTITY="${FRAMECUT_SIGNING_IDENTITY:--}"
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    codesign --force --sign - "${APP_BUNDLE}"
    SIGNATURE_DESCRIPTION="ad-hoc"
else
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
    SIGNATURE_DESCRIPTION="Developer ID"
fi

BUILT_ARCHS="$(lipo -archs "${CONTENTS_DIR}/MacOS/FrameCut")"
"${CONTENTS_DIR}/MacOS/FrameCut" --verify-localizations
echo "Built ${APP_BUNDLE} (${BUILT_ARCHS}; ${SIGNATURE_DESCRIPTION} signature)"
