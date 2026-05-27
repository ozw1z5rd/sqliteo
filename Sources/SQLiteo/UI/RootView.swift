import SwiftUI

@MainActor
struct RootView: View {
    @State private var dbManager = DatabaseManager()
    @State private var queryStore = SQLQueryStore()

    var body: some View {
        ContentView()
            .environmentObject(dbManager)
            .environmentObject(queryStore)
            .onOpenURL { url in
                Task {
                    await dbManager.connect(to: url)
                }
            }
            .focusedSceneValue(\.databaseManager, dbManager)
            .onAppear {
                if let url = DatabaseManager.pendingFileURL {
                    DatabaseManager.pendingFileURL = nil
                    Task {
                        await dbManager.connect(to: url)
                    }
                }
            }
    }
}

// Add focused scene value support for DatabaseManager to allow App-level commands to work
private struct DatabaseManagerKey: FocusedValueKey {
    typealias Value = DatabaseManager
}

extension FocusedValues {
    var databaseManager: DatabaseManager? {
        get { self[DatabaseManagerKey.self] }
        set { self[DatabaseManagerKey.self] = newValue }
    }
}
