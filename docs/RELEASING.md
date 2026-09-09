# Release FrameCut

## Current policy

Until Developer ID signing and Apple notarization are available, publish binaries only as GitHub pre-releases. Keep `unsigned` in asset names and clearly disclose the first-launch limitation. Do not describe ad-hoc-signed builds as Developer ID signed or notarized.

Neither the app nor its DMG/ZIP bundles Homebrew, FFmpeg, ffprobe, Python, or the DMG build tools. Runtime media dependencies are handled by the first-launch wizard.

## Prepare and verify

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` when preparing a new app version. The first published version is 1.2.0, build 3.
2. Add English release notes at `docs/releases/<version>.md`, including installation, platform, unsigned-preview, and runtime-dependency information.
3. Merge the changes into protected `main` through a pull request with passing CI.
4. Work from a clean checkout synchronized with `origin/main`.
5. Run the full media test suite and packaging checks. Building requires Xcode/Swift; packaging additionally requires Python 3.10+ and initial network access to PyPI for the small, hash-pinned build tools.

```bash
./scripts/generate-qa-video.sh .design/fixtures/qa-sample.mp4
FRAMECUT_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
FRAMECUT_CONTENT_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
FRAMECUT_COMPATIBILITY_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
swift test
for shell_script in scripts/*.sh; do zsh -n "$shell_script"; done
./scripts/package-release.sh
codesign --verify --deep --strict --verbose=2 dist/FrameCut.app
lipo dist/FrameCut.app/Contents/MacOS/FrameCut -verify_arch arm64 x86_64
```

`package-release.sh` creates a Universal 2 app, a read-only compressed DMG with a Retina drag-to-Applications layout, an alternative ZIP, and a SHA-256 file for each archive. It mounts the DMG read-only and verifies its contents, app identity/version/signature/architectures, Applications symlink, and Finder layout before promoting the artifacts into `dist/`.

Open the DMG in Finder for a visual check. Verify that the window opens, both icons are readable, and the arrow and bilingual instructions are visible. Test copying the app to a temporary folder if Applications already contains a copy you do not intend to replace.

```bash
open dist/FrameCut-1.2.0-macOS-universal2-unsigned.dmg
cd dist
shasum -a 256 -c FrameCut-1.2.0-macOS-universal2-unsigned.dmg.sha256
shasum -a 256 -c FrameCut-1.2.0-macOS-universal2-unsigned.zip.sha256
```

`dist/`, `.build/`, and local QA media are Git-ignored. Do not commit installers, private samples, or a maintainer's local release checklist.

## Publish with GitHub Actions

After CI passes on the merged commit, create and push its matching annotated version tag:

```bash
git switch main
git pull --ff-only origin main
git tag -a v1.2.0 -m "Release FrameCut 1.2.0 unsigned preview"
git push origin v1.2.0
```

The `Release` workflow requires a `v<major>.<minor>.<patch>` tag matching the bundle version and pointing to a commit contained in `main`. It reruns the full tests, builds and verifies Universal 2 installers, and uploads four assets to a draft before publishing it as a pre-release:

- `FrameCut-<version>-macOS-universal2-unsigned.dmg`
- `FrameCut-<version>-macOS-universal2-unsigned.dmg.sha256`
- `FrameCut-<version>-macOS-universal2-unsigned.zip`
- `FrameCut-<version>-macOS-universal2-unsigned.zip.sha256`

The workflow uses the repository-scoped `GITHUB_TOKEN`; no personal access token or Apple credentials are needed. It does not overwrite existing releases. If uploading fails, inspect the draft and workflow logs before resuming; do not silently replace published assets or move an existing tag.

For manual publication, create a release from the verified tag, use `FrameCut <version> (Unsigned Preview)` as the title, paste the corresponding English release notes, upload all four verified files, and select **Set as a pre-release**.

After publication, download the GitHub-hosted DMG and checksum, verify them again, and inspect the mounted app. GitHub's CI build can differ byte-for-byte from a local build; use the checksum accompanying the downloaded artifact. A separate clean Mac, VM, or test account is still required to validate the complete quarantined first-install experience without the developer's installed dependencies.

## Future Developer ID releases

Once an Apple Developer Program account is available:

1. Create and install a Developer ID Application certificate.
2. Set `FRAMECUT_SIGNING_IDENTITY="Developer ID Application: Team Name (TEAM_ID)"` when invoking the build/package scripts.
3. Submit the app archive or DMG with `notarytool` and wait for `Accepted`.
4. Staple and validate the notarization ticket, then regenerate checksums for the final distributed artifacts.
5. Validate Gatekeeper on a clean system before removing the unsigned/pre-release labels. Update the unsigned-only release workflow as part of that work.

Never commit certificate private keys, `.p12` files, App Store Connect `AuthKey_*.p8` keys, app-specific passwords, or notarization credentials. Use the local Keychain or GitHub Environments and encrypted secrets; `.release-secrets/`, `*.p12`, and `AuthKey_*.p8` are ignored as an additional safeguard.
