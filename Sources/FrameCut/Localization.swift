import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        L10n.text(self == .english ? "language.english" : "language.simplified_chinese")
    }

    static func systemDefault(preferredLanguages: [String]) -> AppLanguage {
        let primary = preferredLanguages.first?.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first
        return primary == "zh" ? .simplifiedChinese : .english
    }

    static func resolve(defaults: UserDefaults, preferredLanguages: [String]) -> AppLanguage {
        if let saved = defaults.string(forKey: LanguagePreferences.languageKey),
           let language = AppLanguage(rawValue: saved) {
            return language
        }
        return systemDefault(preferredLanguages: preferredLanguages)
    }
}

enum L10n {
    // Keep the active language immutable for this process, including background
    // exports. A settings change applies on relaunch, without resetting edits.
    static let language = AppLanguage.resolve(defaults: .standard, preferredLanguages: Locale.preferredLanguages)
    static let locale = language.locale
    private static let placeholderExpression = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static let resourceBundle: Bundle = {
        // SwiftPM's generated accessor can fall back to an absolute build path.
        // Prefer the shipped bundle so installed apps never need build caches.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FrameCut_FrameCut.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    static func bundle(for language: AppLanguage) -> Bundle {
        // SwiftPM normalizes localization folder names to lowercase. Resolve
        // the actual identifier rather than assuming the source folder's case.
        guard let identifier = resourceBundle.localizations.first(where: {
            $0.caseInsensitiveCompare(language.rawValue) == .orderedSame
        }),
              let url = resourceBundle.resourceURL?.appendingPathComponent("\(identifier).lproj"),
              let bundle = Bundle(url: url) else {
            preconditionFailure("Missing localization resource: \(language.rawValue)")
        }
        return bundle
    }

    static func text(_ key: String, language: AppLanguage = language) -> String {
        let translated = bundle(for: language).localizedString(forKey: key, value: nil, table: "Localizable")
        if translated != key || language == .english { return translated }
        return bundle(for: .english).localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: String...) -> String {
        format(key, arguments: arguments, language: language)
    }

    static func format(_ key: String, arguments: [String], language: AppLanguage) -> String {
        let template = text(key, language: language)
        // Substitute only tokens in the original template. A filename or error
        // containing braces or percent signs must not be interpreted as a format.
        let source = template as NSString
        var result = ""
        var cursor = 0
        for match in placeholderExpression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1)))!
            result += index < arguments.count ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        result += source.substring(from: cursor)
        return result
    }

    static func byteCount(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func verifyResources(requireShippedBundle: Bool = false) throws -> [String: Int] {
        if requireShippedBundle {
            let expected = Bundle.main.resourceURL?.appendingPathComponent("FrameCut_FrameCut.bundle")
            guard resourceBundle.bundleURL.standardizedFileURL == expected?.standardizedFileURL else {
                throw ResourceError("Localization resources were loaded outside the application bundle.")
            }
        }

        var reference: [String: String]?
        var counts: [String: Int] = [:]
        let tokens = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func placeholders(_ value: String) -> [String] {
            let source = value as NSString
            return tokens.matches(in: value, range: NSRange(location: 0, length: source.length))
                .map { source.substring(with: $0.range) }.sorted()
        }

        for language in AppLanguage.allCases {
            guard let url = bundle(for: language).url(forResource: "Localizable", withExtension: "strings"),
                  let values = try PropertyListSerialization.propertyList(
                    from: Data(contentsOf: url), options: [], format: nil
                  ) as? [String: String], !values.isEmpty else {
                throw ResourceError("Missing or invalid catalog: \(language.rawValue)")
            }
            if let reference {
                guard Set(values.keys) == Set(reference.keys) else {
                    throw ResourceError("Localization keys do not match: \(language.rawValue)")
                }
                for (key, value) in values where placeholders(value) != placeholders(reference[key]!) {
                    throw ResourceError("Localization placeholders do not match: \(language.rawValue)/\(key)")
                }
            }
            for (key, value) in values {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text(key, language: language) == value else {
                    throw ResourceError("Localization lookup failed: \(language.rawValue)/\(key)")
                }
            }
            reference = reference ?? values
            counts[language.rawValue] = values.count
        }
        return counts
    }

    private struct ResourceError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
