import AppKit
import SwiftUI

final class FrameCutAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MediaCompatibilityPreparer.discardOwnedTemporaryDirectories()
    }
}

@main
struct FrameCutApp: App {
    @NSApplicationDelegateAdaptor(FrameCutAppDelegate.self) private var appDelegate
    @StateObject private var model = VideoEditorModel()
    @StateObject private var setupAssistant = SetupAssistantModel()
    @StateObject private var languagePreferences: LanguagePreferences

    init() {
        // Packaging diagnostics must not open windows or alter user preferences.
        if CommandLine.arguments.contains("--verify-localizations") {
            do {
                let counts = try L10n.verifyResources(requireShippedBundle: true)
                for language in AppLanguage.allCases {
                    print("Localization verified: \(language.rawValue), \(counts[language.rawValue]!) strings")
                }
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Localization verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        _languagePreferences = StateObject(wrappedValue: LanguagePreferences())
        MediaCompatibilityPreparer.discardStaleTemporaryDirectories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environment(\.locale, L10n.locale)
                .frame(minWidth: 980, minHeight: 700)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $setupAssistant.isPresented) {
                    SetupAssistantView(model: setupAssistant)
                        .environment(\.locale, L10n.locale)
                }
                .task {
                    await setupAssistant.runLaunchCheck()
                }
        }
        .defaultSize(width: 1_320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            FrameCutCommands(model: model, setupAssistant: setupAssistant)
        }

        Settings {
            AppSettingsView(preferences: languagePreferences)
        }
    }
}

struct FrameCutCommands: Commands {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var setupAssistant: SetupAssistantModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text(L10n.text("settings.menu"))
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button(L10n.text("menu.open_video")) {
                model.openVideoPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button(L10n.text("menu.export_clip")) {
                model.requestExportReview()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!model.canExport)
        }

        CommandMenu(L10n.text("menu.trim")) {
            Button(model.isPlaying ? L10n.text("transport.pause") : L10n.text("transport.play_range")) {
                model.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!model.canEdit)

            Divider()

            Button(L10n.text("transport.previous_frame")) {
                model.stepFrame(-1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!model.canEdit)

            Button(L10n.text("transport.next_frame")) {
                model.stepFrame(1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!model.canEdit)

            Button(L10n.text("transport.previous_keyframe")) {
                model.jumpToKeyframe(-1)
            }
            .keyboardShortcut(.leftArrow, modifiers: .shift)
            .disabled(!model.canEdit)

            Button(L10n.text("transport.next_keyframe")) {
                model.jumpToKeyframe(1)
            }
            .keyboardShortcut(.rightArrow, modifiers: .shift)
            .disabled(!model.canEdit)

            Divider()

            Button(L10n.text("menu.set_in")) {
                model.setInPointAtCurrentFrame()
            }
            .keyboardShortcut("i", modifiers: [])
            .disabled(!model.canEdit)

            Button(L10n.text("menu.set_out")) {
                model.setOutPointAtCurrentFrame()
            }
            .keyboardShortcut("o", modifiers: [])
            .disabled(!model.canEdit)
        }

        CommandMenu(L10n.text("menu.tools")) {
            Button(L10n.text("menu.runtime_check")) {
                Task { await setupAssistant.presentAndCheck() }
            }
        }
    }
}
