import AppKit

/// Tracks which database files are open in which windows.
/// Allows bringing an existing window to front instead of opening a duplicate.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    // Dual maps let us look up by either key without scanning — both lookups happen on bringToFront and unregister paths
    private var registry: [URL: String] = [:]
    private var reverseRegistry: [String: URL] = [:]

    private init() {}

    /// Associate a file URL with its window's identifier so we can find and activate that window later.
    func register(fileURL: URL, windowIdentifier: String) {
        if let oldIdentifier = registry[fileURL] {
            reverseRegistry.removeValue(forKey: oldIdentifier)
        }
        registry[fileURL] = windowIdentifier
        reverseRegistry[windowIdentifier] = fileURL
    }

    /// Called when a window closes — removes the mapping so a re-open creates a fresh window.
    func unregister(windowIdentifier: String) {
        if let url = reverseRegistry.removeValue(forKey: windowIdentifier) {
            registry.removeValue(forKey: url)
        }
    }

    func unregister(fileURL: URL) {
        if let identifier = registry.removeValue(forKey: fileURL) {
            reverseRegistry.removeValue(forKey: identifier)
        }
    }

    /// Resolves symlinks so opening the same database through different paths is still detected as a duplicate.
    func isOpen(fileURL: URL) -> Bool {
        let resolved = fileURL.resolvingSymlinksInPath()
        return registry.keys.contains { $0.resolvingSymlinksInPath() == resolved }
    }

    /// Finds the NSWindow by its tagged identifier and orders it front, activating the app.
    func bringToFront(fileURL: URL) {
        guard let identifier = registry[fileURL] ?? registry.first(where: { $0.key.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath() })?.value else { return }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
