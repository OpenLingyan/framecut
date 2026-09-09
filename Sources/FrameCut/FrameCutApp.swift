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

    init() {
        MediaCompatibilityPreparer.discardStaleTemporaryDirectories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 700)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $setupAssistant.isPresented) {
                    SetupAssistantView(model: setupAssistant)
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
    }
}

struct FrameCutCommands: Commands {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var setupAssistant: SetupAssistantModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开视频…") {
                model.openVideoPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("导出所选片段…") {
                model.requestExportReview()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!model.canExport)
        }

        CommandMenu("剪辑") {
            Button(model.isPlaying ? "暂停" : "播放所选区间") {
                model.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!model.canEdit)

            Divider()

            Button("上一帧") {
                model.stepFrame(-1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!model.canEdit)

            Button("下一帧") {
                model.stepFrame(1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!model.canEdit)

            Button("上一关键帧") {
                model.jumpToKeyframe(-1)
            }
            .keyboardShortcut(.leftArrow, modifiers: .shift)
            .disabled(!model.canEdit)

            Button("下一关键帧") {
                model.jumpToKeyframe(1)
            }
            .keyboardShortcut(.rightArrow, modifiers: .shift)
            .disabled(!model.canEdit)

            Divider()

            Button("将当前帧设为入点") {
                model.setInPointAtCurrentFrame()
            }
            .keyboardShortcut("i", modifiers: [])
            .disabled(!model.canEdit)

            Button("将当前帧设为出点") {
                model.setOutPointAtCurrentFrame()
            }
            .keyboardShortcut("o", modifiers: [])
            .disabled(!model.canEdit)
        }

        CommandMenu("工具") {
            Button("运行环境自检…") {
                Task { await setupAssistant.presentAndCheck() }
            }
        }
    }
}
