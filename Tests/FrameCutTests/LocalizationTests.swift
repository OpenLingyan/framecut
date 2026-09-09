import Foundation
import XCTest
@testable import FrameCut

final class LocalizationTests: XCTestCase {
    func testAllChineseSystemVariantsUseSimplifiedChinese() {
        for identifier in ["zh", "zh-CN", "zh-Hans-CN", "zh-Hant-TW", "zh-HK", "zh_HK", "ZH-hant"] {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: [identifier]), .simplifiedChinese)
        }
    }

    func testNonChineseAndEmptySystemLanguagesUseEnglish() {
        for languages in [["en-US"], ["fr-FR"], ["ja-JP"], ["de-DE", "zh-Hans"], [], [""]] {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: languages), .english)
        }
    }

    @MainActor
    func testFirstLaunchPersistsSystemChoiceWithoutChangingSelfCheck() async {
        for (system, expected) in [("zh-Hant-TW", AppLanguage.simplifiedChinese), ("fr-FR", .english)] {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: SetupAssistantModel.completionKey)
            let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]

            let preferences = LanguagePreferences(defaults: defaults, preferredLanguages: [system])

            XCTAssertEqual(preferences.activeLanguage, expected)
            XCTAssertEqual(preferences.selectedLanguage, expected)
            XCTAssertEqual(defaults.string(forKey: LanguagePreferences.languageKey), expected.rawValue)
            XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), [expected.rawValue])
            XCTAssertTrue(defaults.bool(forKey: SetupAssistantModel.completionKey))
            XCTAssertFalse(preferences.needsRestart)
            XCTAssertEqual(
                UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
                globalLanguages
            )
        }
    }

    @MainActor
    func testSavedChoiceWinsAfterSystemLanguageChanges() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = LanguagePreferences(defaults: defaults, preferredLanguages: ["zh-CN"])

        let relaunched = LanguagePreferences(defaults: defaults, preferredLanguages: ["en-US"])

        XCTAssertEqual(relaunched.activeLanguage, .simplifiedChinese)
        XCTAssertEqual(relaunched.selectedLanguage, .simplifiedChinese)
    }

    @MainActor
    func testSelectionIsSavedImmediatelyAndTakesEffectOnRelaunch() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LanguagePreferences(defaults: defaults, preferredLanguages: ["zh-CN"])

        preferences.select(.english)

        XCTAssertEqual(preferences.selectedLanguage, .english)
        XCTAssertEqual(preferences.activeLanguage, .simplifiedChinese)
        XCTAssertTrue(preferences.needsRestart)
        XCTAssertEqual(defaults.string(forKey: LanguagePreferences.languageKey), "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        let reloadedDefaults = UserDefaults(suiteName: suite)!
        let relaunched = LanguagePreferences(defaults: reloadedDefaults, preferredLanguages: ["zh-Hant"])
        XCTAssertEqual(relaunched.activeLanguage, .english)
        XCTAssertFalse(relaunched.needsRestart)
    }

    @MainActor
    func testSelectingActiveLanguageClearsRestartNotice() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LanguagePreferences(defaults: defaults, preferredLanguages: ["en-US"])
        preferences.select(.simplifiedChinese)
        XCTAssertTrue(preferences.needsRestart)
        preferences.select(.english)
        XCTAssertFalse(preferences.needsRestart)
        XCTAssertEqual(defaults.string(forKey: LanguagePreferences.languageKey), "en")
    }

    @MainActor
    func testInvalidSavedLanguageIsRepairedUsingSystemDefault() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unsupported-language", forKey: LanguagePreferences.languageKey)

        let preferences = LanguagePreferences(defaults: defaults, preferredLanguages: ["zh-HK"])

        XCTAssertEqual(preferences.activeLanguage, .simplifiedChinese)
        XCTAssertEqual(defaults.string(forKey: LanguagePreferences.languageKey), "zh-Hans")
    }

    func testBothCatalogsHaveCompleteMatchingKeysAndPlaceholders() throws {
        let counts = try L10n.verifyResources()
        XCTAssertEqual(Set(counts.keys), Set(AppLanguage.allCases.map(\.rawValue)))
        XCTAssertEqual(counts["en"], counts["zh-Hans"])
        XCTAssertGreaterThan(counts["en"] ?? 0, 200)
    }

    func testExplicitLanguageLookupDoesNotFollowSystemLanguage() {
        XCTAssertEqual(L10n.text("settings.title", language: .english), "Settings")
        XCTAssertEqual(L10n.text("settings.title", language: .simplifiedChinese), "设置")
        XCTAssertEqual(L10n.text("media.stereo", language: .english), "Stereo")
        XCTAssertEqual(L10n.text("media.stereo", language: .simplifiedChinese), "立体声")
        XCTAssertEqual(L10n.text("language.simplified_chinese", language: .english), "简体中文")
    }

    func testFormattingPreservesUnicodeFilenamesAndLiteralTokens() {
        let filename = "旅行-100%-{1}-🎞️"
        XCTAssertEqual(
            L10n.format("export.suggested_filename", arguments: [filename, "mp4"], language: .english),
            "\(filename)-clip.mp4"
        )
        XCTAssertEqual(
            L10n.format("export.suggested_filename", arguments: [filename, "mov"], language: .simplifiedChinese),
            "\(filename)-片段.mov"
        )
    }

    func testMissingKeyAndMissingArgumentsRemainDiagnosable() {
        XCTAssertEqual(L10n.text("test.missing", language: .simplifiedChinese), "test.missing")
        XCTAssertEqual(
            L10n.format("player.frame_position", arguments: ["10"], language: .english),
            "Frame 10 / {1}"
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FrameCut.LocalizationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}
