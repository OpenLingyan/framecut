#!/usr/bin/env python3
"""Mount and verify a release image without opening Finder or application windows."""

import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from ds_store import DSStore


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(image, version, architecture):
    subprocess.run(["hdiutil", "verify", str(image)], check=True)
    image_info = plistlib.loads(subprocess.check_output(["hdiutil", "imageinfo", "-plist", str(image)]))
    require(image_info["Format"] == "UDZO", "The release must be a compressed, read-only UDZO image.")

    with tempfile.TemporaryDirectory(prefix="framecut-dmg-check-") as temporary:
        mount = Path(temporary) / "volume"
        mount.mkdir()
        subprocess.run(
            ["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)],
            check=True,
        )
        try:
            visible = {entry.name for entry in mount.iterdir() if not entry.name.startswith(".")}
            require(visible == {"FrameCut.app", "Applications"}, "Unexpected files in the installer.")
            require((mount / "Applications").is_symlink(), "The Applications shortcut is missing.")
            require(os.readlink(mount / "Applications") == "/Applications", "Incorrect installation target.")
            require((mount / ".background.tiff").is_file(), "The Retina installer background is missing.")
            require((mount / ".VolumeIcon.icns").is_file(), "The volume icon is missing.")

            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                require(store["FrameCut.app"]["Iloc"] == (180, 210), "Incorrect application icon position.")
                require(store["Applications"]["Iloc"] == (480, 210), "Incorrect Applications icon position.")
                window = store["."]["bwsp"]
                require("660, 468" in window["WindowBounds"], "Incorrect installer window size.")
                require(not window["ShowToolbar"] and not window["ShowSidebar"], "Unexpected Finder chrome.")
                view = store["."]["icvp"]
                require(view["backgroundType"] == 2 and view.get("backgroundImageAlias"), "Missing background reference.")
                require(view["iconSize"] == 112, "Incorrect installer icon size.")

            app = mount / "FrameCut.app"
            with (app / "Contents/Info.plist").open("rb") as source:
                info = plistlib.load(source)
            require(info["CFBundleIdentifier"] == "com.openlingyan.framecut", "Unexpected app identifier.")
            require(info["CFBundleShortVersionString"] == version, "The app and release versions differ.")
            require(info["LSMinimumSystemVersion"] == "14.0", "Unexpected minimum macOS version.")
            require(set(info["CFBundleLocalizations"]) == {"en", "zh-Hans"}, "Missing app languages.")
            for language in ("en", "zh-Hans"):
                require(
                    (app / f"Contents/Resources/{language}.lproj/InfoPlist.strings").is_file(),
                    f"Missing native app localization: {language}",
                )
            subprocess.run(
                [str(app / "Contents/MacOS/FrameCut"), "--verify-localizations"], check=True
            )
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            architectures = ["arm64", "x86_64"] if architecture == "universal2" else [architecture]
            require(all(value in {"arm64", "x86_64"} for value in architectures), "Unknown architecture.")
            subprocess.run(
                ["lipo", str(app / "Contents/MacOS/FrameCut"), "-verify_arch", *architectures],
                check=True,
            )
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)

    print(f"DMG verification passed: {image.name}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: verify-dmg.py <image.dmg> <version> <universal2|arm64|x86_64>")
    verify(Path(sys.argv[1]).resolve(), sys.argv[2], sys.argv[3])
