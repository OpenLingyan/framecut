# FrameCut

English | [Simplified Chinese](docs/README-zh.md)

FrameCut is a native macOS video trimming app. It opens local videos through a file picker or drag and drop, navigates by actual frames and keyframes, sets inclusive In and Out points, and saves the selected segment as MP4 or MOV.

## Features

- Reads and exports media locally with AVFoundation; videos are never uploaded.
- Scans video sample timestamps to show the actual frame count and provide precise previous-frame and next-frame navigation.
- Detects sync samples for previous-keyframe and next-keyframe navigation.
- Provides a thumbnail timeline with a playhead, draggable In/Out handles, and a highlighted selection.
- Treats the Out point as inclusive and automatically extends the export range to the next frame boundary.
- Validates the In point, Out point, duration, frame count, and output format before presenting the macOS save panel.
- Shows export progress and supports cancellation, error recovery, and revealing the result in Finder.
- Evaluates the source codec, resolution, frame rate, and bitrate per pixel to recommend a smart compression target. It preserves the original dimensions and uses HEVC while estimating the target bitrate, output size, and size reduction.
- Uses a tiered compatibility pipeline: system-native containers such as MP4 and MOV are handled by AVFoundation; AVI, MKV, WebM, and other containers are inspected with FFmpeg and remuxed when possible; if the video or audio remains unreadable, FrameCut creates an H.264/AAC compatibility preview.
- Reads the original source for compatibility-aware smart export and uses content-adaptive x265 CRF 24 compression calibrated across varied test material, so proxy-preview loss is not carried into the final output.
- Runs an environment self-check on first launch. When media components are missing, a guided installer helps install Homebrew first and then the required packages through Homebrew. The check is marked complete in local preferences only after every verification passes; otherwise, it runs again on the next launch.
- Supports drag and drop and a complete set of keyboard shortcuts.

## Requirements

- macOS 14 Sonoma or later.
- Official preview builds are intended to support both Apple Silicon and Intel Macs as Universal 2 applications.
- Building from source requires Xcode 15 or later and Swift 5.10+.
- Native formats require no additional dependencies. Compatibility previews for other containers and codecs, as well as content-adaptive compression, require FFmpeg. Install it locally with `brew install ffmpeg`.

FrameCut does not bundle Homebrew or FFmpeg binaries. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for component purposes, installation boundaries, and license information.

## Download and Installation

FrameCut currently has neither an Apple Developer ID signature nor Apple notarization. Binary builds published on GitHub Releases should be treated as unsigned previews. macOS will block the first launch until the user confirms **Open Anyway** in **System Settings → Privacy & Security**.

Download only from the official [`OpenLingyan/framecut` Releases](https://github.com/OpenLingyan/framecut/releases) page and verify the included SHA-256 checksum before running the app. Do not disable Gatekeeper or run untrusted Terminal bypass commands. See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for the complete procedure, compatibility notes, and risk information.

## Media Compatibility

| Type | Common formats |
|---|---|
| Video codecs | H.264/AVC, H.265/HEVC, AV1, VP9, VP8, MPEG-4 Part 2 (Xvid/DivX), MPEG-2, MPEG-1, ProRes, DNxHD/DNxHR, Motion JPEG, VC-1/WMV, Theora, CineForm |
| Audio codecs | AAC, MP3, AC-3, E-AC-3, Opus, Vorbis, FLAC, ALAC, PCM, WMA, DTS |
| Containers and elementary streams | MP4/M4V, MOV, AVI/DivX, MKV, WebM, WMV/ASF, MPG/MPEG/VOB, TS/M2TS/MTS/M4TS, MXF, FLV/F4V, 3GP/3G2, OGV, RM/RMVB, DV/MOD/TOD, and raw H.264/H.265/AV1 streams |

The exact decoding range depends on the decoders enabled in the installed FFmpeg build. Standard exports use H.264/AAC for broad compatibility, while smart compression uses H.265/HEVC with AAC.

## Build the macOS App

```bash
./scripts/build-app.sh
open dist/FrameCut.app
```

The script first generates a complete `FrameCut.icns` icon set from `Resources/FrameCut.png`, then builds a Universal 2 app containing both `arm64` and `x86_64` binaries and applies an ad-hoc signature. To build for the current architecture only, specify it explicitly, for example:

```bash
FRAMECUT_BUILD_ARCHS=arm64 ./scripts/build-app.sh
```

Generate a ZIP archive and SHA-256 checksum suitable for GitHub Releases:

```bash
./scripts/package-release.sh
```

These artifacts are suitable for unsigned preview releases. Removing Gatekeeper's unidentified-developer warning still requires Apple Developer ID signing and notarization. Maintainers should follow [`docs/RELEASING.md`](docs/RELEASING.md).

For development, run the app directly with:

```bash
./scripts/run.sh
./scripts/run.sh /absolute/path/to/sample-video.mp4
```

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Open a video | `⌘O` |
| Export the selected segment | `⌘E` |
| Play or pause the selection | `Space` |
| Previous or next frame | `←` / `→` |
| Previous or next keyframe | `⇧←` / `⇧→` |
| Set the current frame as the In or Out point | `I` / `O` |

## Testing

```bash
swift test
```

The test suite covers timecodes, binary frame lookup, keyframe navigation, and inclusive Out-point calculations.

## Contributing and Security

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, test-media rules, and pull request requirements. Do not disclose security vulnerabilities publicly; follow [`SECURITY.md`](SECURITY.md) and use GitHub's private vulnerability reporting channel.

## Privacy and File Safety

FrameCut reads, analyzes, previews, and exports videos entirely on the local Mac. It does not upload video data and never modifies the source file. Exports create a new file at the location explicitly selected in the system save panel; macOS handles confirmation if the destination already exists.

The runtime environment self-check also runs locally. If Homebrew or FFmpeg is missing, the installer needs network access to the official Homebrew installer and package services. This access is used only to install or update runtime components; no video or video-derived content is sent to Homebrew, FFmpeg, or a FrameCut service.

## License

FrameCut source code is available under the [MIT License](LICENSE). Homebrew, FFmpeg, and their components are not part of the FrameCut source code and remain subject to their respective licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for details.
