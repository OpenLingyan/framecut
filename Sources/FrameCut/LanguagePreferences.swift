import Combine
import Foundation

@MainActor
final class LanguagePreferences: ObservableObject {
    nonisolated static let languageKey = "FrameCut.language.v1"

    let activeLanguage: AppLanguage
    @Published private(set) var selectedLanguage: AppLanguage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let language = AppLanguage.resolve(defaults: defaults, preferredLanguages: preferredLanguages)
        activeLanguage = language
        selectedLanguage = language
        persist(language)
    }

    var needsRestart: Bool { selectedLanguage != activeLanguage }

    func select(_ language: AppLanguage) {
        persist(language)
        selectedLanguage = language
    }

    private func persist(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.languageKey)
        // This is the app's preferences domain, not the global system domain.
        // AppKit uses it for standard menus and file dialogs on the next launch.
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}
