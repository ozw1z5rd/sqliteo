import SwiftUI

@MainActor
struct RootView: View {
    @State private var dbManager = DatabaseManager()
    @State private var queryStore = SQLQueryStore()
    @State private var windowID = UUID().uuidString  // Identifies this window's NSWindow for WindowManager lookups

    var body: some View {
        ContentView()
            .environmentObject(dbManager)
            .environmentObject(queryStore)
            .onOpenURL { url in
                // Don't open a duplicate — activate the existing window instead
                if WindowManager.shared.isOpen(fileURL: url) {
                    WindowManager.shared.bringToFront(fileURL: url)
                } else {
                    Task {
                        await dbManager.connect(to: url)
                    }
                }
            }
            .focusedSceneValue(\.databaseManager, dbManager)
            .focusedSceneValue(\.queryStore, queryStore)
            .onAppear {
                // Set app icon from asset catalog (SPM doesn't auto-link it)
                let resourceBundle: Bundle = {
                    let mainPath = Bundle.main.bundleURL.appendingPathComponent("SQLiteo_SQLiteo.bundle").path
                    let buildPath = Bundle.main.bundleURL
                        .deletingLastPathComponent()
                        .appendingPathComponent("SQLiteo_SQLiteo.bundle").path
                    return Bundle(path: mainPath) ?? Bundle(path: buildPath) ?? Bundle.main
                }()
                if let iconURL = resourceBundle.url(forResource: "AppIcon", withExtension: "png"),
                   let appIcon = NSImage(contentsOf: iconURL)
                {
                    NSApp.applicationIconImage = appIcon
                }

                if let url = DatabaseManager.pendingFileURL {
                    DatabaseManager.pendingFileURL = nil
                    Task {
                        await dbManager.connect(to: url)
                    }
                }
                // Hand the window ID to the manager so connect(to:) can register it with WindowManager
                dbManager.windowIdentifier = windowID
            }
            .onDisappear {
                WindowManager.shared.unregister(windowIdentifier: windowID)
            }
            // Tag the NSWindow with our UUID so WindowManager can find it when bringToFront is called.
            .background {
                WindowIdentifierAccessor(windowID: windowID)
            }
    }
}

/// Sets the NSWindow identifier to our windowID so WindowManager can find the right window.
private struct WindowIdentifierAccessor: NSViewRepresentable {
    let windowID: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let identifier = NSUserInterfaceItemIdentifier(windowID)
            window.identifier = identifier
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Add focused scene value support for DatabaseManager to allow App-level commands to work
private struct DatabaseManagerKey: FocusedValueKey {
    typealias Value = DatabaseManager
}

private struct QueryStoreKey: FocusedValueKey {
    typealias Value = SQLQueryStore
}

extension FocusedValues {
    var databaseManager: DatabaseManager? {
        get { self[DatabaseManagerKey.self] }
        set { self[DatabaseManagerKey.self] = newValue }
    }

    var queryStore: SQLQueryStore? {
        get { self[QueryStoreKey.self] }
        set { self[QueryStoreKey.self] = newValue }
    }
}
