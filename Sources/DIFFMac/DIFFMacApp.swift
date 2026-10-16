import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
    }
}

@main
struct DIFFMacApp: App {
    @StateObject private var store = AppStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup(AppMetadata.name, id: "main-window") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 720)
                .onOpenURL { url in
                    store.handleOpenURL(url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await store.refreshCurrentMode() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("Workspace") {
                Button("Show Pull Requests") {
                    Task { await store.showWorkspaceMode(.pulls) }
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Show Branches") {
                    Task { await store.showWorkspaceMode(.branches) }
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Show Code") {
                    Task { await store.showWorkspaceMode(.code) }
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                Button("Show Diff Tab") {
                    store.activeTab = .diff
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Show Discussion Tab") {
                    store.activeTab = .discussion
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Show Checks Tab") {
                    store.activeTab = .checks
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Show Timeline Tab") {
                    store.activeTab = .timeline
                }
                .keyboardShortcut("4", modifiers: [.command, .option])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520)
        }
    }
}
