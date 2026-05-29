import AppKit
import GRDB
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FileActions {
    static func openFile(dbManager: DatabaseManager?, openWindow: OpenWindowAction? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType("org.sqlite.sqlite"),
            UTType.database,
            UTType.data,
        ].compactMap { $0 }

        panel.allowedContentTypes += [
            UTType(filenameExtension: "sqlite"),
            UTType(filenameExtension: "db"),
            UTType(filenameExtension: "sqlite3"),
        ].compactMap { $0 }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                // If this file is already open in another window, bring that window to front
                if WindowManager.shared.isOpen(fileURL: url) {
                    WindowManager.shared.bringToFront(fileURL: url)
                    return
                }
                if let dbManager, dbManager.fileURL == nil {
                    Task {
                        await dbManager.connect(to: url)
                    }
                } else if let openWindow {
                    // This window already has a database open — open a new window for the new file
                    DatabaseManager.pendingFileURL = url
                    openWindow(id: "main")
                }
               
            }
        }
    }

    static func createNewFile(dbManager: DatabaseManager?, openWindow: OpenWindowAction? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType("org.sqlite.sqlite"),
            UTType.database,
            UTType.data,
        ].compactMap { $0 }

        panel.allowedContentTypes += [
            UTType(filenameExtension: "sqlite"),
            UTType(filenameExtension: "db"),
            UTType(filenameExtension: "sqlite3"),
        ].compactMap { $0 }

        panel.nameFieldStringValue = "NewDatabase.sqlite"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    if !FileManager.default.fileExists(atPath: url.path) {
                        FileManager.default.createFile(
                            atPath: url.path, contents: nil, attributes: nil)
                    }
                    // If this file is already open, bring that window to front
                    if WindowManager.shared.isOpen(fileURL: url) {
                        WindowManager.shared.bringToFront(fileURL: url)
                        return
                    }
                    if let dbManager, dbManager.fileURL == nil {
                         await dbManager.connect(to: url)
                    } else if let openWindow {
                         DatabaseManager.pendingFileURL = url
                         openWindow(id: "main")
                    }
                }
            }
        }
    }

    static func importCSV(dbManager: DatabaseManager?, openWindow: OpenWindowAction?) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.commaSeparatedText]

        openPanel.begin { openResponse in
            guard openResponse == .OK, let csvURL = openPanel.url else { return }

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [
                UTType("org.sqlite.sqlite"),
                UTType.database,
                UTType.data,
            ].compactMap { $0 }
            savePanel.allowedContentTypes += [
                UTType(filenameExtension: "sqlite"),
                UTType(filenameExtension: "db"),
                UTType(filenameExtension: "sqlite3"),
            ].compactMap { $0 }
            savePanel.nameFieldStringValue = csvURL.deletingPathExtension().lastPathComponent + ".sqlite"

            savePanel.begin { saveResponse in
                guard saveResponse == .OK, let dbURL = savePanel.url else { return }

                Task {
                    do {
                        try await Self.importCSVToDatabase(csvURL: csvURL, dbURL: dbURL)
                        if let dbManager, dbManager.fileURL == nil {
                            await dbManager.connect(to: dbURL)
                        } else if let openWindow {
                            DatabaseManager.pendingFileURL = dbURL
                            openWindow(id: "main")
                        }
                    } catch {
                        if let dbManager {
                            dbManager.errorMessage = "Import failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private static func importCSVToDatabase(csvURL: URL, dbURL: URL) async throws {
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { throw ImportError.notEnoughRows }

        let headers = try parseCSVLine(lines[0])
        guard !headers.isEmpty else { throw ImportError.emptyHeader }
        // Sanitize column names — replace spaces/special chars with underscores
        let columns = headers.map { sanitizeColumnName($0) }

        var allValues: [[String]] = []
        for i in 1..<lines.count {
            let values = try parseCSVLine(lines[i])
            let padded = values + Array(repeating: "", count: max(0, columns.count - values.count))
            allValues.append(Array(padded.prefix(columns.count)))
        }

        let rows = allValues
        let queue = try DatabaseQueue(path: dbURL.path)
        try await queue.write { db in
            let colDefs = columns.map { "\"\($0)\" TEXT" }.joined(separator: ", ")
            try db.execute(sql: "CREATE TABLE imported_data (\(colDefs))")

            let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
            let insertSQL = "INSERT INTO imported_data (\(columns.map { "\"\($0)\"" }.joined(separator: ", "))) VALUES (\(placeholders))"

            for values in rows {
                try db.execute(sql: insertSQL, arguments: StatementArguments(values))
            }
        }
    }

    private static func parseCSVLine(_ line: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                if inQuotes {
                    // Look ahead for another quote (escaped quote)
                    // Simple approach: toggle and append
                    inQuotes = false
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func sanitizeColumnName(_ name: String) -> String {
        let sanitized = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[^a-zA-Z0-9_]"#, with: "_", options: .regularExpression)
        return sanitized.isEmpty ? "column" : sanitized
    }

    enum ImportError: Error, LocalizedError {
        case notEnoughRows
        case emptyHeader

        var errorDescription: String? {
            switch self {
            case .notEnoughRows: return "CSV must have at least a header row and one data row"
            case .emptyHeader: return "CSV header row is empty"
            }
        }
    }
}
