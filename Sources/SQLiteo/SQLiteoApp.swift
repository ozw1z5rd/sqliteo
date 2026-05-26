import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct SQLiteoApp: App {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.databaseManager) var dbManager
    @StateObject private var recentFiles = RecentFilesManager.shared

    init() {
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Database...") {
                    FileActions.createNewFile(dbManager: dbManager)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open SQLite File...") {
                    FileActions.openFile(dbManager: dbManager)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                RefreshCommand()
            }

            CommandGroup(after: .newItem) {
                OpenRecentMenu(dbManager: dbManager)
                    .environmentObject(recentFiles)
            }

            CommandGroup(replacing: .appInfo) {
                Button("About SQLiteo") {
                    let aboutWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                        styleMask: [.titled, .closable],
                        backing: .buffered,
                        defer: false
                    )
                    aboutWindow.title = "About SQLiteo"
                    aboutWindow.contentView = NSHostingView(rootView: AboutView())
                    aboutWindow.center()
                    aboutWindow.makeKeyAndOrderFront(nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("SQLiteo Help") {
                    if let url = URL(string: "https://github.com/adamghill/sqliteo") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct RefreshCommand: View {
    @FocusedValue(\.databaseManager) var dbManager

    var body: some View {
        Button("Refresh Database") {
            if let manager = dbManager {
                Task {
                    await manager.refreshDatabase()
                }
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(dbManager?.fileURL == nil)
    }
}

private struct OpenRecentMenu: View {
    var dbManager: DatabaseManager?
    @EnvironmentObject private var recentFiles: RecentFilesManager

    var body: some View {
        Menu("Open Recent") {
            if recentFiles.recentURLs.isEmpty {
                Text("No Recent Files")
                    .disabled(true)
            } else {
                ForEach(recentFiles.recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        openRecentFile(url)
                    }
                }

                Divider()

                Button("Clear Menu") {
                    recentFiles.clear()
                }
            }
        }
        .disabled(recentFiles.recentURLs.isEmpty)
    }

    private func openRecentFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if let dbManager, dbManager.fileURL == nil {
            Task {
                await dbManager.connect(to: url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
