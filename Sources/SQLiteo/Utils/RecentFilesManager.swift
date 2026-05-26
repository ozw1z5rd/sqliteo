import Foundation

@MainActor
final class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()

    @Published var recentURLs: [URL] = []

    private let maxCount = 10
    private let defaultsKey = "RecentFiles"

    private init() {
        load()
    }

    func add(_ url: URL) {
        var urls = recentURLs
        urls.removeAll { $0.path == url.path }
        urls.insert(url, at: 0)
        if urls.count > maxCount {
            urls = Array(urls.prefix(maxCount))
        }
        recentURLs = urls
        save()
    }

    func clear() {
        recentURLs = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            let bookmarkDataArray = try JSONDecoder().decode([Data].self, from: data)
            var urls: [URL] = []
            for bookmarkData in bookmarkDataArray {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withoutUI,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale)
                {
                    urls.append(url)
                }
            }
            recentURLs = urls
        } catch {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private func save() {
        let bookmarkDataArray = recentURLs.compactMap { url -> Data? in
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
        }
        guard let data = try? JSONEncoder().encode(bookmarkDataArray) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
