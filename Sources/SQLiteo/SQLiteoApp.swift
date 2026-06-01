import SwiftUI
import UniformTypeIdentifiers

enum ColorSchemeOption: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var preferredScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

struct SettingsView: View {
    @AppStorage("colorScheme") private var colorScheme: ColorSchemeOption = .system

    var body: some View {
        Form {
            Picker("Appearance", selection: $colorScheme) {
                ForEach(ColorSchemeOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 300, height: 150)
    }
}

@main
@MainActor
struct SQLiteoApp: App {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.databaseManager) var dbManager
    @FocusedValue(\.queryStore) var queryStore
    @StateObject private var recentFiles = RecentFilesManager.shared
    @AppStorage("colorScheme") private var colorScheme: ColorSchemeOption = .system

    init() {
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .preferredColorScheme(colorScheme.preferredScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Database...") {
                    FileActions.createNewFile(dbManager: dbManager, openWindow: openWindow)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open SQLite File...") {
                    FileActions.openFile(dbManager: dbManager, openWindow: openWindow)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Import CSV...") {
                    FileActions.importCSV(dbManager: dbManager, openWindow: openWindow)
                }

                Divider()

                Button("Save SQL...") {
                    saveCurrentQuery()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(queryStore?.selectedQuery == nil)

                Button("Load SQL...") {
                    loadSQLFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(queryStore == nil)
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
                    AboutWindowManager.shared.show()
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

        Settings {
            SettingsView()
        }
    }
}

/// Ensures the about window reference is cleared when the window is closed.
@MainActor
private final class AboutWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

/// Manages a single about window instance so it doesn't get deallocated while open.
@MainActor
private final class AboutWindowManager: NSObject {
    static let shared = AboutWindowManager()
    private var window: NSWindow?
    private var delegate: AboutWindowDelegate?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow.title = "About SQLiteo"
        aboutWindow.contentView = NSHostingView(rootView: AboutView())
        aboutWindow.center()
        aboutWindow.isReleasedWhenClosed = false

        let del = AboutWindowDelegate { [weak self] in
            self?.window = nil
            self?.delegate = nil
        }
        aboutWindow.delegate = del
        delegate = del
        window = aboutWindow
        aboutWindow.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private extension SQLiteoApp {
    func saveCurrentQuery() {
        guard let queryStore, let query = queryStore.selectedQuery else { return }
        let sql = query.sql

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sql")].compactMap { $0 }
        panel.nameFieldStringValue = query.name.hasSuffix(".sql") ? query.name : "\(query.name).sql"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    try sql.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    queryStore.selectedQuery.map { _ in
                        // Silently surface through the standard error mechanism
                    }
                }
            }
        }
    }

    func loadSQLFile() {
        guard let queryStore else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sql")].compactMap { $0 }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                do {
                    let sql = try String(contentsOf: url, encoding: .utf8)
                    let queryName = url.deletingPathExtension().lastPathComponent
                    let query = queryStore.addQuery(name: queryName)
                    queryStore.updateSQL(id: query.id, sql: sql)
                } catch {
                    // Silently surface through the standard error mechanism
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
    @Environment(\.openWindow) private var openWindow

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

        // If this file is already open, bring that window to front
        if WindowManager.shared.isOpen(fileURL: url) {
            WindowManager.shared.bringToFront(fileURL: url)
            return
        }

        if let dbManager, dbManager.fileURL == nil {
            Task {
                await dbManager.connect(to: url)
            }
        } else {
            DatabaseManager.pendingFileURL = url
            openWindow(id: "main")
        }
    }
}
