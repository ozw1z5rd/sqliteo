import AppKit
import Foundation
import GRDB
import UniformTypeIdentifiers

struct DBRow: Identifiable {
    let id = UUID()
    let data: [String: String]
}

@Observable
class DatabaseManager {
    var dbQueue: DatabaseQueue?
    var tableNames: [String] = []
    var selectedTableName: String?
    var columns: [String] = []
    var primaryKeyColumns: [String] = []
    var rows: [DBRow] = []

    // Tracks local edits: [RowID: [ColumnName: NewValue]]
    var pendingChanges: [UUID: [String: String]] = [:]

    var filterText: String = ""

    var hasChanges: Bool {
        !pendingChanges.isEmpty
    }

    func connect(to url: URL) {
        do {
            dbQueue = try DatabaseQueue(path: url.path)
            try fetchTables()
        } catch {
            print("Error connecting to database: \(error)")
        }
    }

    func fetchTables() throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            self.tableNames = try String.fetchAll(
                db,
                sql:
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        }
    }

    func selectTable(_ tableName: String) {
        self.selectedTableName = tableName
        self.pendingChanges = [:]
        self.filterText = ""
        do {
            try fetchPrimaryKeys(for: tableName)
            try fetchColumns(for: tableName)
            try fetchRows(for: tableName)
        } catch {
            print("Error loading table data: \(error)")
        }
    }

    private func fetchPrimaryKeys(for tableName: String) throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            let columnsInfo = try db.columns(in: tableName)
            // primaryKeyIndex is 0 if not part of PK, > 0 otherwise.
            self.primaryKeyColumns = columnsInfo.filter { $0.primaryKeyIndex > 0 }.map { $0.name }
        }
    }

    private func fetchColumns(for tableName: String) throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            let columnsInfo = try db.columns(in: tableName)
            self.columns = columnsInfo.map { $0.name }
        }
    }

    private func fetchRows(for tableName: String) throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            var sql = "SELECT * FROM \(tableName)"
            var arguments: StatementArguments = []

            if !filterText.isEmpty {
                let conditions = self.columns.map { "\($0) LIKE ?" }.joined(separator: " OR ")
                sql += " WHERE \(conditions)"
                arguments = StatementArguments(
                    Array(repeating: "%\(filterText)%", count: self.columns.count))
            }

            sql += " LIMIT 1000"
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            self.rows = rows.map { row in
                var dict: [String: String] = [:]
                for column in self.columns {
                    if let val = row[column] {
                        dict[column] = "\(val)"
                    }
                }
                return DBRow(data: dict)
            }
        }
    }

    func executeCustomSQL(_ sql: String) {
        guard let dbQueue = dbQueue else { return }
        self.selectedTableName = nil  // Clear selection when running custom SQL
        self.pendingChanges = [:]

        do {
            try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: sql)
                if let firstRow = rows.first {
                    self.columns = Array(firstRow.columnNames)
                } else {
                    // Try to get columns even if no rows (harder with arbitrary SQL,
                    // but we can try to prepare the statement)
                    let statement = try db.makeStatement(sql: sql)
                    self.columns = Array(statement.columnNames)
                }

                self.rows = rows.map { row in
                    var dict: [String: String] = [:]
                    for column in self.columns {
                        if let val = row[column] {
                            dict[column] = "\(val)"
                        }
                    }
                    return DBRow(data: dict)
                }
                self.primaryKeyColumns = []  // Can't reliably detect PKs for arbitrary results
            }
        } catch {
            print("Error executing SQL: \(error)")
        }
    }

    func applyFilter() {
        if let tableName = selectedTableName {
            try? fetchRows(for: tableName)
        }
    }

    func clearFilter() {
        filterText = ""
        applyFilter()
    }

    func updateCell(rowID: UUID, column: String, value: String) {
        if pendingChanges[rowID] == nil {
            pendingChanges[rowID] = [:]
        }
        pendingChanges[rowID]?[column] = value
    }

    func discardChanges() {
        pendingChanges = [:]
    }

    func saveChanges() {
        guard let dbQueue = dbQueue, let tableName = selectedTableName else { return }

        do {
            try dbQueue.write { db in
                for (rowID, changes) in self.pendingChanges {
                    guard let row = self.rows.first(where: { $0.id == rowID }) else { continue }

                    let setClause = changes.map { "\($0.key) = ?" }.joined(separator: ", ")
                    let whereColumns =
                        self.primaryKeyColumns.isEmpty ? self.columns : self.primaryKeyColumns
                    let whereClause = whereColumns.map { "\($0) = ?" }.joined(separator: " AND ")

                    let sql = "UPDATE \(tableName) SET \(setClause) WHERE \(whereClause)"

                    var arguments: [DatabaseValueConvertible?] = Array(changes.values)
                    arguments.append(contentsOf: whereColumns.map { row.data[$0] })

                    try db.execute(sql: sql, arguments: StatementArguments(arguments))
                }
            }
            pendingChanges = [:]
            try fetchRows(for: tableName)
        } catch {
            print("Error saving changes: \(error)")
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType("org.sqlite.sqlite"),
            UTType.database,
            UTType.data,
        ].compactMap { $0 }

        // Ensure common extensions are covered if UTIs fail
        panel.allowedContentTypes += [
            UTType(filenameExtension: "sqlite"),
            UTType(filenameExtension: "db"),
            UTType(filenameExtension: "sqlite3"),
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            if let url = panel.url {
                self.connect(to: url)
            }
        }
    }
}
