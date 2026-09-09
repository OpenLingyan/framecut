# Localization

FrameCut supports English (`en`) and Simplified Chinese (`zh-Hans`).

## Selection and persistence

- A valid `FrameCut.language.v1` value in the application's `UserDefaults` domain takes precedence over system preferences.
- Without a valid saved value, inspect the first entry of `Locale.preferredLanguages`. A Chinese language code (`zh`, including `zh-Hans`, `zh-Hant`, and regional variants) selects Simplified Chinese. Any other code, or an empty list, selects English.
- Save the result immediately. Existing installations without this key are initialized in the same way; runtime component verification state is preserved.
- Settings saves changes immediately. The current process keeps its active language until relaunch, avoiding resets to media selection, exports, or editing state.
- Store `AppleLanguages` in the **application domain only** alongside the app language key so standard AppKit menus and dialogs use the selected language after relaunch. Never change the global macOS language preference.

For the packaged app, macOS manages these preferences at `~/Library/Preferences/com.openlingyan.framecut.plist`. Use the Settings UI rather than editing the plist while the app or preferences daemon is running.

## Language packs

Application-owned text, including menus, accessibility labels, tooltips, errors, compression descriptions, and setup guidance, lives in:

- `Sources/FrameCut/Resources/en.lproj/Localizable.strings`
- `Sources/FrameCut/Resources/zh-Hans.lproj/Localizable.strings`

Native bundle display names and the document type description live in the corresponding `Resources/<language>.lproj/InfoPlist.strings` files. Product and codec names, keyboard symbols, timecodes, user filenames, URLs, commands, and unmodified upstream FFmpeg/Homebrew diagnostics are not translated. macOS owns the text of standard system dialogs; it is not duplicated in these catalogs.

Use stable semantic keys with `L10n.text("settings.title")`. For variable content, use `L10n.format("player.frame_position", currentFrame, totalFrames)`. Both arguments are strings and the catalog uses zero-based tokens such as `{0}` and `{1}`. Translators may reorder tokens, but must preserve their counts. Avoid string concatenation for sentences. Substitution processes only the original template, so percent signs, emoji, and braces in filenames remain literal.

Add each key to both catalogs with nonempty values. Keep the files sorted by key. English is the fallback language. Format user-visible numbers and byte counts using `L10n.locale`, not an unrelated system locale.

## Resources in installed apps

SwiftPM processes the catalogs into `FrameCut_FrameCut.bundle`. The build script copies that bundle into `FrameCut.app/Contents/Resources`, along with native `InfoPlist.strings` resources. `L10n` explicitly prioritizes the shipped bundle; installed apps must not depend on SwiftPM's absolute build-cache fallback. Resource lookup accommodates SwiftPM's lowercase localization folder names.

## Verification

```bash
python3 scripts/check-localizations.py
swift test
./scripts/build-app.sh
dist/FrameCut.app/Contents/MacOS/FrameCut --verify-localizations
```

The source check detects missing or duplicate keys, empty translations, inconsistent placeholders, and common unlocalized UI literals. Unit tests cover system language variants, saved preferences, invalid preferences, restart behavior, self-check preservation, both catalogs, and literal user input. CI and release workflows run these checks.

The app's diagnostic flag checks every translated value, key parity, placeholders, and the shipped resource location without opening windows or writing preferences. App packaging runs it automatically, and DMG verification repeats it from the mounted image. It is a packaging diagnostic, not an end-user launch mode.

Before releasing, inspect both languages in the main window, Settings, export review, and component setup. Check long English labels at the minimum supported window size. Confirm that changing language displays the restart notice, then relaunch to verify menus and saved selection.
