import CodeEditorView
import LanguageSupport
import SwiftUI
import AppKit

private struct CustomTheme {
    static let dark = Theme(
        colourScheme: .dark,
        fontName: "SFMono-Medium",
        fontSize: 13.0,
        textColour: NSColor(red: 0.87, green: 0.87, blue: 0.88, alpha: 1.0),
        commentColour: NSColor(red: 0.51, green: 0.55, blue: 0.59, alpha: 1.0),
        stringColour: NSColor(red: 0.94, green: 0.53, blue: 0.46, alpha: 1.0),
        characterColour: NSColor(red: 0.84, green: 0.79, blue: 0.53, alpha: 1.0),
        numberColour: NSColor(red: 0.81, green: 0.74, blue: 0.40, alpha: 1.0),
        identifierColour: NSColor(red: 0.41, green: 0.72, blue: 0.64, alpha: 1.0),
        keywordColour: NSColor(red: 0.94, green: 0.51, blue: 0.69, alpha: 1.0),
        backgroundColour: NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0),
        currentLineColour: NSColor(red: 0.19, green: 0.20, blue: 0.22, alpha: 1.0),
        selectionColour: NSColor(red: 0.40, green: 0.44, blue: 0.51, alpha: 1.0),
        cursorColour: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        invisiblesColour: NSColor(red: 0.33, green: 0.37, blue: 0.42, alpha: 1.0)
    )

    static let light = Theme(
        colourScheme: .light,
        fontName: "SFMono-Medium",
        fontSize: 13.0,
        textColour: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
        commentColour: NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0),
        stringColour: NSColor(red: 0.76, green: 0.24, blue: 0.16, alpha: 1.0),
        characterColour: NSColor(red: 0.14, green: 0.19, blue: 0.81, alpha: 1.0),
        numberColour: NSColor(red: 0.0, green: 0.05, blue: 1.0, alpha: 1.0),
        identifierColour: NSColor(red: 0.23, green: 0.50, blue: 0.54, alpha: 1.0),
        keywordColour: NSColor(red: 0.63, green: 0.28, blue: 0.62, alpha: 1.0),
        backgroundColour: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        currentLineColour: NSColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1.0),
        selectionColour: NSColor(red: 0.73, green: 0.84, blue: 0.99, alpha: 1.0),
        cursorColour: NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        invisiblesColour: NSColor(red: 0.84, green: 0.84, blue: 0.84, alpha: 1.0)
    )
}

enum Tab: String, CaseIterable, Identifiable {
    case data = "Data"
    case schema = "Schema"
    var id: String { rawValue }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject private var dbManager: DatabaseManager
    @EnvironmentObject private var queryStore: SQLQueryStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: Tab = .data
    @State private var tableFilter = ""
    @State private var queryFilter = ""

    // Autocomplete State
    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var currentWord = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isCyclingAutocomplete = false
    @State private var autocompleteCycleIndex = 0
    @State private var ignoreNextSQLChange = false
    @State private var lastInsertedSuggestionLength = 0

    // Inline rename state
    @State private var editingQueryID: UUID?
    @State private var editingQueryName: String = ""

    // Editor & Sidebar UI State
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("sqlQueriesHeight") private var savedSqlQueriesHeight: Double = 150
    @State private var activeSqlQueriesHeight: Double? = nil
    @State private var dragStartHeight: Double? = nil
    @State private var isDraggingDivider = false

    // Export state
    @State private var exportAllRows = false
    @State private var showExportConfirm = false

    // Editor Resizing State
    @AppStorage("sqlEditorHeight") private var savedSqlEditorHeight: Double = 150
    @State private var activeSqlEditorHeight: Double? = nil
    @State private var editorDragStartHeight: Double? = nil
    @State private var isDraggingEditorDivider = false

    // Event monitor for Cmd+Return query execution
    @State private var queryEventMonitor: Any? = nil

    private var sqlQueriesHeight: Double {
        activeSqlQueriesHeight ?? savedSqlQueriesHeight
    }

    private var sqlEditorHeight: Double {
        activeSqlEditorHeight ?? savedSqlEditorHeight
    }

    private let sqlKeywords = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "AND", "OR", "NOT",
        "ORDER BY", "GROUP BY", "JOIN", "INNER JOIN", "LEFT JOIN", "ON", "AS",
        "ASC", "DESC", "LIMIT", "OFFSET", "PRAGMA",
    ]

    private var filteredTableNames: [String] {
        if tableFilter.isEmpty {
            return dbManager.tableNames
        }
        return dbManager.tableNames.filter { $0.fuzzyMatch(query: tableFilter) }
    }

    private var filteredQueries: [SQLQuery] {
        let queries = queryStore.queries
        if queryFilter.isEmpty {
            return queries
        }
        return queries.filter { $0.name.fuzzyMatch(query: queryFilter) }
    }

    // Local state for editor text, synced with queryStore
    @State private var editorSQL: String = ""

    private var selectedQuerySQL: Binding<String> {
        Binding(
            get: { editorSQL },
            set: { newValue in
                editorSQL = newValue
                if let id = queryStore.selectedQueryID {
                    queryStore.updateSQL(id: id, sql: newValue)
                }
            }
        )
    }

    private var tableSelectionBinding: Binding<String?> {
        Binding(
            get: { dbManager.selectedTableName },
            set: { dbManager.selectedTableName = $0 }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            detail
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if dbManager.fileURL != nil {
                sqlQueriesSection
                    .frame(height: max(60, sqlQueriesHeight))

                resizeHandle(isDragging: $isDraggingDivider,
                             startHeight: $dragStartHeight,
                             activeHeight: $activeSqlQueriesHeight,
                             savedHeight: $savedSqlQueriesHeight,
                             currentHeight: sqlQueriesHeight)
            }

            List(filteredTableNames, id: \.self, selection: tableSelectionBinding) { tableName in
                Text(tableName)
                    .tag(tableName)
            }
            .navigationTitle("Tables")
            .listStyle(.sidebar)

            Divider()

            tableFilterBar

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
        .onChange(of: dbManager.selectedTableName) { newValue in
            if let tableName = newValue {
                queryStore.selectedQueryID = nil
                Task {
                    await dbManager.selectTable(tableName)
                }
            }
        }
        .onChange(of: queryStore.selectedQueryID) { newID in
            editorPosition = CodeEditor.Position()
            editorSQL = queryStore.selectedQuery?.sql ?? ""
        }
        .onChange(of: dbManager.fileURL) { newURL in
            if let url = newURL {
                queryStore.configure(for: url)
            }
        }
    }

    private var tableFilterBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("Filter", text: $tableFilter)
                .textFieldStyle(.plain)
                .font(.caption)
            if !tableFilter.isEmpty {
                Button {
                    tableFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            if let query = queryStore.selectedQuery {
                sqlQueryEditor(query: query)
            } else if dbManager.selectedTableName != nil {
                tableDetailView
            } else {
                emptyStateView
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Spacer()
                Button {
                    Task { await dbManager.refreshDatabase() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(dbManager.fileURL == nil)

                Button(action: {
                    FileActions.openFile(dbManager: dbManager, openWindow: openWindow)
                }) {
                    Label("Open Database", systemImage: "folder")
                }

                Button(action: {
                    FileActions.importCSV(dbManager: dbManager, openWindow: openWindow)
                }) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private func sqlQueryEditor(query: SQLQuery) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CodeEditor(
                    text: selectedQuerySQL,
                    position: $editorPosition,
                    messages: $editorMessages,
                    language: .none,
                    layout: CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)
                )
                .environment(
                    \.codeEditorTheme,
                    colorScheme == .dark ? CustomTheme.dark : CustomTheme.light
                )
                .frame(height: max(60, sqlEditorHeight))
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: editorSQL) { newValue in
                    if ignoreNextSQLChange {
                        ignoreNextSQLChange = false
                        return
                    }
                    isCyclingAutocomplete = false
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !Task.isCancelled else { return }
                        await updateSuggestions(for: newValue)
                    }
                }
                .modifier(SQLEditorKeyHandler(
                    isCyclingAutocomplete: $isCyclingAutocomplete,
                    showSuggestions: $showSuggestions,
                    suggestions: suggestions,
                    editorPosition: $editorPosition,
                    onSuggest: { Task { await updateSuggestions(for: queryStore.selectedQuery?.sql ?? "") } },
                    onCycle: { cycleSuggestion() }
                ))

                if showSuggestions && !suggestions.isEmpty {
                    suggestionBar
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage = dbManager.errorMessage {
                    errorBar(message: errorMessage)
                }
            }

            queryRunBar(query: query)

            resizeHandle(isDragging: $isDraggingEditorDivider,
                         startHeight: $editorDragStartHeight,
                         activeHeight: $activeSqlEditorHeight,
                         savedHeight: $savedSqlEditorHeight,
                         currentHeight: sqlEditorHeight)

            DataTableView()
            StatusBar(selectedTab: $selectedTab, showTabs: false)
        }
        .navigationTitle(query.name)
        .overlay(LoadingOverlay(isLoading: dbManager.isLoading))
        .onAppear {
            queryEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                    guard let q = queryStore.selectedQuery else { return event }
                    let text = textToExecute(for: q)
                    dbManager.runQuery(text)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = queryEventMonitor {
                NSEvent.removeMonitor(monitor)
                queryEventMonitor = nil
            }
        }
        .alert("Export Confirmation", isPresented: $showExportConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Export All") {
                Task { await doExportAll() }
            }
        } message: {
            Text("This will export all \(dbManager.totalRows) rows. The file may be large. Continue?")
        }
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        insertSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isCyclingAutocomplete && index == autocompleteCycleIndex
                                    ? Color.accentColor
                                    : Color.accentColor.opacity(0.2)
                            )
                            .foregroundColor(
                                isCyclingAutocomplete && index == autocompleteCycleIndex
                                    ? Color.white
                                    : .primary
                            )
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

    private func errorBar(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(message)
                .foregroundColor(.red)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dbManager.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }

    private func queryRunBar(query: SQLQuery) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    let text = textToExecute(for: query)
                    dbManager.runQuery(text)
                } label: {
                    Label("Run Query", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)

                if dbManager.isLoading {
                    Button {
                        dbManager.cancelQuery()
                    } label: {
                        Label("Cancel", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if !dbManager.rows.isEmpty {
                    Toggle("Export all rows", isOn: $exportAllRows)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)

                    Button {
                        if exportAllRows {
                            Task { await prepareExportAll() }
                        } else {
                            exportCSV(rows: dbManager.rows.map { $0.data })
                        }
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var tableDetailView: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .data:
                DataTableView()
            case .schema:
                SchemaView()
            }
            StatusBar(selectedTab: $selectedTab)
        }
        .overlay(LoadingOverlay(isLoading: dbManager.isLoading))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            if dbManager.fileURL != nil {
                Text("Select a table or a SQL query")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("Open a database")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Button("Open SQLite File...") {
                    FileActions.openFile(dbManager: dbManager, openWindow: openWindow)
                }
                .buttonStyle(.borderedProminent)
                Button("New Database...") {
                    FileActions.createNewFile(dbManager: dbManager, openWindow: openWindow)
                }
                .buttonStyle(.bordered)
                Button("Import CSV...") {
                    FileActions.importCSV(dbManager: dbManager, openWindow: openWindow)
                }
                .buttonStyle(.bordered)
            }
            if let error = dbManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared Helpers

    private func resizeHandle(
        isDragging: Binding<Bool>,
        startHeight: Binding<Double?>,
        activeHeight: Binding<Double?>,
        savedHeight: Binding<Double>,
        currentHeight: Double
    ) -> some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        isDragging.wrappedValue = true
                        if startHeight.wrappedValue == nil {
                            startHeight.wrappedValue = currentHeight
                        }
                        if let start = startHeight.wrappedValue {
                            activeHeight.wrappedValue = max(60, start + value.translation.height)
                        }
                    }
                    .onEnded { _ in
                        if let finalHeight = activeHeight.wrappedValue {
                            savedHeight.wrappedValue = finalHeight
                        }
                        startHeight.wrappedValue = nil
                        activeHeight.wrappedValue = nil
                        isDragging.wrappedValue = false
                    }
            )
    }

    // MARK: - SQL Queries Sidebar Section

    private var sqlQueriesSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SQL Queries")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    let newQuery = queryStore.addQuery()
                    dbManager.clearDataForSQLConsole()
                    queryStore.selectedQueryID = newQuery.id
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New SQL Query")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            List(
                selection: Binding(
                    get: { queryStore.selectedQueryID },
                    set: { newID in
                        if let id = newID {
                            queryStore.selectedQueryID = id
                            dbManager.clearDataForSQLConsole()
                        }
                    }
                )
            ) {
                ForEach(filteredQueries) { query in
                    queryRow(for: query)
                        .tag(query.id)
                }
            }
            .listStyle(.sidebar)

            if queryStore.queries.count > 3 {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Filter queries", text: $queryFilter)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !queryFilter.isEmpty {
                        Button {
                            queryFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func queryRow(for query: SQLQuery) -> some View {
        if editingQueryID == query.id {
            TextField(
                "Query name", text: $editingQueryName,
                onCommit: {
                    queryStore.renameQuery(id: query.id, to: editingQueryName)
                    editingQueryID = nil
                }
            )
            .textFieldStyle(.plain)
            .font(.body)
            .onExitCommand {
                editingQueryID = nil
            }
        } else {
            Text(query.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Rename") {
                        editingQueryID = query.id
                        editingQueryName = query.name
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        queryStore.deleteQuery(id: query.id)
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

        let components = lastWord.split(separator: ".")
        let aliasColumnPrefix =
            components.count == 2
            ? String(components[1]).lowercased() : (lastWord.hasSuffix(".") ? "" : nil)

        if let prefix = aliasColumnPrefix {
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
        } else if previousWord == "FROM" || previousWord == "JOIN" {
            tableMatches = dbManager.tableNames.filter {
                $0.localizedCaseInsensitiveContains(wordToMatch)
            }
        } else if previousWord == "WHERE" || previousWord == "ON" || previousWord == "SELECT" {
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
        } else {
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

        let allMatches = Array(Set(keywordMatches + tableMatches + columnMatches))
            .filter { $0.caseInsensitiveCompare(wordToMatch) != .orderedSame }
            .sorted()

        suggestions = allMatches
        showSuggestions = !suggestions.isEmpty
    }

    private func insertSuggestion(_ suggestion: String) {
        guard let queryID = queryStore.selectedQueryID,
            var sql = queryStore.selectedQuery?.sql
        else { return }

        let charactersToDrop =
            isCyclingAutocomplete ? lastInsertedSuggestionLength : currentWord.count

        let prefix: String
        if currentWord.contains(".") {
            let parts = currentWord.components(separatedBy: ".")
            prefix = (parts.first ?? "") + "."
        } else {
            prefix = ""
        }

        if currentWord.isEmpty && !isCyclingAutocomplete {
            sql += suggestion + " "
        } else {
            sql = String(sql.dropLast(charactersToDrop)) + "\(prefix)\(suggestion) "
        }

        isCyclingAutocomplete = false
        queryStore.updateSQL(id: queryID, sql: sql)
        currentWord = ""
        showSuggestions = false
    }

    private func cycleSuggestion() {
        guard let queryID = queryStore.selectedQueryID,
            var sql = queryStore.selectedQuery?.sql
        else { return }

        let charactersToDrop: Int
        if !isCyclingAutocomplete {
            isCyclingAutocomplete = true
            autocompleteCycleIndex = 0
            charactersToDrop = currentWord.count
        } else {
            autocompleteCycleIndex = (autocompleteCycleIndex + 1) % suggestions.count
            charactersToDrop = lastInsertedSuggestionLength
        }

        let suggestion = suggestions[autocompleteCycleIndex]
        let prefix: String
        if currentWord.contains(".") {
            let parts = currentWord.components(separatedBy: ".")
            prefix = (parts.first ?? "") + "."
        } else {
            prefix = ""
        }

        let textToInsert = prefix + suggestion
        sql = String(sql.dropLast(charactersToDrop)) + textToInsert
        lastInsertedSuggestionLength = textToInsert.count

        ignoreNextSQLChange = true
        queryStore.updateSQL(id: queryID, sql: sql)

        let highlightLength = max(0, textToInsert.utf16.count - currentWord.utf16.count)
        let highlightLocation = sql.utf16.count - highlightLength
        editorPosition.selections = [
            NSRange(location: max(0, highlightLocation), length: highlightLength)
        ]
    }

    private func textToExecute(for query: SQLQuery) -> String {
        let sql = query.sql
        let nsRange = editorPosition.selections.first ?? NSRange(location: 0, length: 0)
        guard let range = Range(nsRange, in: sql) else {
            let startRange = sql.startIndex..<sql.startIndex
            return String(sql[query.rangeToExecute(withSelection: startRange)])
        }
        let result = query.rangeToExecute(withSelection: range)
        return String(sql[result])
    }

    private func prepareExportAll() async {
        let count = dbManager.totalRows
        if count > 5000 {
            showExportConfirm = true
        } else {
            await doExportAll()
        }
    }

    private func doExportAll() async {
        do {
            let data = try await dbManager.fetchAllRowsForExport()
            guard let url = showSavePanel() else { return }
            writeCSV(rows: data.rows, columns: data.columns, to: url)
        } catch {
            dbManager.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportCSV(rows: [[String: String]]) {
        guard let url = showSavePanel() else { return }
        writeCSV(rows: rows, columns: dbManager.columns, to: url)
    }

    private func showSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "export.csv"
        var url: URL?
        if panel.runModal() == .OK {
            url = panel.url
        }
        return url
    }

    private func writeCSV(rows: [[String: String]], columns: [String], to url: URL) {
        var csv = columns.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        for row in rows {
            let line = columns.map { col in escapeCSV(row[col] ?? "") }.joined(separator: ",")
            csv += line + "\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            dbManager.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

#Preview {
    ContentView()
        .environmentObject(DatabaseManager())
        .environmentObject(SQLQueryStore())
}

// MARK: - Key Handler for macOS 13 compatibility

private struct SQLEditorKeyHandler: ViewModifier {
    @Binding var isCyclingAutocomplete: Bool
    @Binding var showSuggestions: Bool
    var suggestions: [String]
    @Binding var editorPosition: CodeEditor.Position
    var onSuggest: () -> Void
    var onCycle: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.return, phases: .down) { press in
                    if isCyclingAutocomplete {
                        isCyclingAutocomplete = false
                        showSuggestions = false
                        if let first = editorPosition.selections.first {
                            editorPosition.selections = [
                                NSRange(location: first.upperBound, length: 0)
                            ]
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.space, phases: .down) { press in
                    if press.modifiers.contains(.control) {
                        onSuggest()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.tab, phases: .down) { press in
                    if showSuggestions && !suggestions.isEmpty {
                        onCycle()
                        return .handled
                    }
                    return .ignored
                }
        } else {
            content
        }
    }
}
