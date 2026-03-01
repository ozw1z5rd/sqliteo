import SwiftUI

@main
@MainActor
struct SQLiteoApp: App {
    @State private var dbManager = DatabaseManager()
    @State private var queryStore = SQLQueryStore()

    init() {
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dbManager)
                .environment(queryStore)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open SQLite File...") {
                    dbManager.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
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
