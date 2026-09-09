import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var preferences: LanguagePreferences

    var body: some View {
        Form {
            Section {
                Picker(L10n.text("settings.language"), selection: Binding(
                    get: { preferences.selectedLanguage },
                    set: { preferences.select($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .accessibilityIdentifier("app-language-picker")

                Text(L10n.text("settings.language_policy"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.text("settings.general"))
            }

            if preferences.needsRestart {
                Label(L10n.text("settings.restart_required"), systemImage: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(FrameCutColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.text("settings.saved_locally"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 250)
        .environment(\.locale, L10n.locale)
        .navigationTitle(L10n.text("settings.title"))
    }
}
