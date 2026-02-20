import CodeEditor
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case data = "Data"
    case schema = "Schema"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(DatabaseManager.self) private var dbManager
    @State private var showSQLConsole = false
    @State private var selectedTab: Tab = .data
    @State private var customSQL = ""

    // Autocomplete State
    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var currentWord = ""
    @State private var debounceTask: Task<Void, Never>?

    private let sqlKeywords = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "AND", "OR", "NOT",
        "ORDER BY", "GROUP BY", "JOIN", "INNER JOIN", "LEFT JOIN", "ON", "AS",
        "ASC", "DESC", "LIMIT", "OFFSET", "PRAGMA",
    ]

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(
                    dbManager.tableNames, id: \.self,
                    selection: Bindable(dbManager).selectedTableName
                ) { tableName in
                    Text(tableName)
                        .tag(tableName)
                }
                .navigationTitle("Tables")
                .listStyle(.sidebar)

                if let fileURL = dbManager.fileURL {
                    Divider()
                    FileMetadataView(
                        fileName: fileURL.lastPathComponent,
                        filePath: fileURL.path,
                        fileSize: dbManager.fileSize,
                        dateModified: dbManager.modificationDate ?? Date()
                    )
                    .padding()
                }
            }
            .onChange(of: dbManager.selectedTableName) { _, newValue in
                if let tableName = newValue {
                    Task {
                        await dbManager.selectTable(tableName)
                        showSQLConsole = false
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: dbManager.openFile) {
                        Label("Open Database", systemImage: "folder")
                    }
                }
            }
        } detail: {
            if showSQLConsole {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        CodeEditor(source: $customSQL, language: .sql)
                            .frame(height: 150)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .onChange(of: customSQL) { _, newValue in
                                debounceTask?.cancel()
                                debounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 150_000_000)
                                    guard !Task.isCancelled else { return }
                                    await updateSuggestions(for: newValue)
                                }
                            }
                            .onKeyPress(.space, phases: .down) { press in
                                if press.modifiers.contains(.control) {
                                    Task {
                                        await updateSuggestions(for: customSQL)
                                    }
                                    return .handled
                                }
                                return .ignored
                            }

                        if showSuggestions && !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestions, id: \.self) { suggestion in
                                        Button {
                                            insertSuggestion(suggestion)
                                        } label: {
                                            Text(suggestion)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .background(.regularMaterial)
                            .cornerRadius(6)
                            .shadow(radius: 2)
                            .padding(.leading, 8)
                            .padding(.bottom, 8)
                        }
                    }

                    HStack {
                        Button {
                            Task {
                                await dbManager.executeCustomSQL(customSQL)
                            }
                        } label: {
                            Label("Run Query", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)

                        Spacer()
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    DataTableView()
                    StatusBar(selectedTab: $selectedTab, showTabs: false)
                }
                .navigationTitle("SQL Console")
            } else if let tableName = dbManager.selectedTableName {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .data:
                        DataTableView()
                    case .schema:
                        SchemaView()
                    }

                    StatusBar(selectedTab: $selectedTab)
                }
                .navigationTitle(tableName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await dbManager.saveChanges()
                            }
                        } label: {
                            Label("Save", systemImage: "checkmark.circle.fill")
                        }
                        .disabled(!dbManager.hasChanges)
                        .help("Save changes to database")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dbManager.discardChanges()
                        } label: {
                            Label("Discard", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(!dbManager.hasChanges)
                        .help("Discard unsaved changes")
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "square.grid.3x2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    if dbManager.fileURL != nil {
                        Text("Select a table or open the SQL Console")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Open a database")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Open SQLite File...") {
                            dbManager.openFile()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let error = dbManager.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            if dbManager.fileURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSQLConsole.toggle()
                        if showSQLConsole {
                            dbManager.clearDataForSQLConsole()
                        }
                    } label: {
                        Label(
                            "SQL Console",
                            systemImage: showSQLConsole ? "terminal.fill" : "terminal")
                    }
                    .help("Toggle SQL Console (Cmd+T)")
                }
            }
        }
    }

    // MARK: - Autocomplete Logic

    private func updateSuggestions(for text: String) async {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        guard let lastWord = words.last else {
            showSuggestions = false
            suggestions = []
            return
        }

        currentWord = lastWord
        let previousWord = words.dropLast().last?.uppercased()

        var keywordMatches: [String] = []
        var tableMatches: [String] = []
        var columnMatches: [String] = []

        let wordToMatch = lastWord.lowercased()

        // Handle alias patterns like `P.` -> suggest columns
        let components = lastWord.split(separator: ".")
        let aliasColumnPrefix =
            components.count == 2
            ? String(components[1]).lowercased() : (lastWord.hasSuffix(".") ? "" : nil)

        // If typing an alias (e.g. "P.")
        if let prefix = aliasColumnPrefix {
            // Suggest columns for tables present in the query
            let queryUpper = text.uppercased()
            let tablesInQuery = dbManager.tableNames.filter { queryUpper.contains($0.uppercased()) }
            if !tablesInQuery.isEmpty {
                let columnsForQuery = await dbManager.columns(for: tablesInQuery)
                columnMatches = columnsForQuery.filter {
                    $0.localizedCaseInsensitiveContains(prefix)
                }
            } else {
                columnMatches = dbManager.columns.filter {
                    $0.localizedCaseInsensitiveContains(prefix)
                }
            }
        }
        // If the previous word indicates we need a table (FROM, JOIN)
        else if previousWord == "FROM" || previousWord == "JOIN" {
            tableMatches = dbManager.tableNames.filter {
                $0.localizedCaseInsensitiveContains(wordToMatch)
            }
        }
        // If the previous word indicates we need a column (WHERE, ON, SELECT)
        else if previousWord == "WHERE" || previousWord == "ON" || previousWord == "SELECT" {
            // Find tables mentioned in the query to suggest their columns
            let queryUpper = text.uppercased()
            let tablesInQuery = dbManager.tableNames.filter { queryUpper.contains($0.uppercased()) }

            if !tablesInQuery.isEmpty {
                let columnsForQuery = await dbManager.columns(for: tablesInQuery)
                columnMatches = columnsForQuery.filter {
                    $0.localizedCaseInsensitiveContains(wordToMatch)
                }
            } else {
                columnMatches = dbManager.columns.filter {
                    $0.localizedCaseInsensitiveContains(wordToMatch)
                }
            }
        }
        // Otherwise, general autocomplete
        else {
            if !wordToMatch.isEmpty {
                keywordMatches = sqlKeywords.filter {
                    $0.localizedCaseInsensitiveContains(wordToMatch)
                }
                tableMatches = dbManager.tableNames.filter {
                    $0.localizedCaseInsensitiveContains(wordToMatch)
                }
                columnMatches = dbManager.columns.filter {
                    $0.localizedCaseInsensitiveContains(wordToMatch)
                }
            }
        }

        let allMatches = Array(Set(keywordMatches + tableMatches + columnMatches)).sorted()

        suggestions = allMatches
        showSuggestions = !suggestions.isEmpty
    }

    private func insertSuggestion(_ suggestion: String) {
        if currentWord.isEmpty {
            // We were typing a new word after a space, so just append
            customSQL += suggestion + " "
        } else {
            // Check if it's an alias form, e.g., P.
            if currentWord.contains(".") {
                let parts = currentWord.components(separatedBy: ".")
                let prefix = parts.first ?? ""
                customSQL =
                    String(customSQL.dropLast(currentWord.count)) + "\(prefix).\(suggestion) "
            } else {
                customSQL = String(customSQL.dropLast(currentWord.count)) + "\(suggestion) "
            }
        }

        currentWord = ""  // Reset after insertion
        showSuggestions = false
    }
}
