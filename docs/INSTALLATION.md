# Install FrameCut

## Supported systems

- macOS 14 Sonoma or later.
- Apple Silicon and Intel Macs (Universal 2).
- Homebrew and FFmpeg for non-native media formats and content-adaptive compression.

FrameCut currently has no Apple Developer ID signature or Apple notarization. GitHub binary releases are unsigned previews: macOS cannot verify their developer identity or confirm an Apple notarization check. A DMG makes installation more convenient; it does not remove this limitation.

## Download and verify

Download these two matching files only from the official [FrameCut Releases](https://github.com/OpenLingyan/framecut/releases) page:

- `FrameCut-1.2.0-macOS-universal2-unsigned.dmg`
- `FrameCut-1.2.0-macOS-universal2-unsigned.dmg.sha256`

In Terminal, change to your download directory and verify the checksum (substitute the downloaded version when necessary):

```bash
cd ~/Downloads
shasum -a 256 -c FrameCut-1.2.0-macOS-universal2-unsigned.dmg.sha256
```

Continue only if the result is `OK`. A checksum detects corrupted downloads or mismatches with the release manifest; it does not replace Developer ID signing or notarization.

## Drag to install

1. Double-click the verified `.dmg` file. Finder opens an installation window with FrameCut on the left and Applications on the right.
2. Drag **FrameCut** onto **Applications** and wait for copying to finish. If replacing an older version, quit FrameCut first and confirm replacement only if intended.
3. Open **Applications** and launch the installed **FrameCut**. Do not run it from the mounted installer.
4. Eject the FrameCut disk from the Finder sidebar when copying is complete. You may then remove the downloaded DMG.

If the window does not open automatically, select the mounted FrameCut disk under **Locations** in Finder. A ZIP and matching `.zip.sha256` checksum are available as an alternative: verify the ZIP, extract it, and drag the app into Applications.

## First launch of an unsigned preview

1. Try opening the installed FrameCut once. macOS may block it because its developer cannot be verified.
2. Open **System Settings > Privacy & Security** and scroll to **Security**.
3. Find the blocked FrameCut app, select **Open Anyway**, authenticate, and confirm the launch.
4. Subsequent launches of the same installed version work normally.

Do not disable Gatekeeper or run Terminal commands to remove quarantine attributes. On a managed company or school Mac, **Open Anyway** may be unavailable; ask the administrator or build from reviewed source. There is no need to install Python or disk-image packaging tools.

## Runtime component check

On first launch, FrameCut checks Homebrew, FFmpeg, and ffprobe. If components are present, it opens the main interface. Otherwise, its wizard guides Homebrew installation and then installs FFmpeg through Homebrew. Successful verification is recorded locally; a failed check runs again on the next launch.

Component installation requires network access. Video reading, analysis, preview, and export stay on the local Mac; videos are never uploaded.

## Build from source

If you prefer not to allow an unsigned binary, review the source and build it yourself with Xcode 15 or later and Swift 5.10+:

```bash
git clone https://github.com/OpenLingyan/framecut.git
cd framecut
swift test
./scripts/build-app.sh
open dist/FrameCut.app
```
