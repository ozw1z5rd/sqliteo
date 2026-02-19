import Foundation
import GRDB
import Testing

@testable import SQLitizer

@MainActor
@Suite("Database Manager Tests")
final class DatabaseManagerTests {
    var dbURL: URL!
    var manager: DatabaseManager!

    init() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        dbURL = tempDir.appendingPathComponent("test_db_\(UUID().uuidString).sqlite")

        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                        CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER);
                        INSERT INTO users (name, age) VALUES ('Alice', 30);
                        INSERT INTO users (name, age) VALUES ('Bob', 25);
                        INSERT INTO users (name, age) VALUES ('Charlie', 35);
                        
                        CREATE TABLE posts (post_id INTEGER PRIMARY KEY, title TEXT, user_id INTEGER);
                        INSERT INTO posts (title, user_id) VALUES ('Hello World', 1);
                        INSERT INTO posts (title, user_id) VALUES ('Swift Rocks', 2);
                        
                        CREATE TABLE tags (name TEXT PRIMARY KEY) WITHOUT ROWID;
                        INSERT INTO tags (name) VALUES ('swift');
                        INSERT INTO tags (name) VALUES ('programming');
                        
                        CREATE VIEW user_names AS SELECT name FROM users;
                    """)
        }

        manager = DatabaseManager()
        await manager.connect(to: dbURL)
    }

    deinit {
        // No MainActor cleanup needed for URL
        if let url = dbURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(atPath: url.path)
        }
    }

    @Test("Connection and initialization populate correct metadata")
    func connectionAndInitialization() async throws {
        #expect(manager.currentFileURL == dbURL)
        #expect(manager.currentFileSize != nil)

        #expect(manager.tableNames.sorted() == ["posts", "tags", "users"])
    }

    @Test("Selecting a standard table populates columns and rows")
    func selectingStandardTable() async throws {
        await manager.selectTable("users")

        #expect(manager.selectedTableName == "users")
        #expect(manager.columns == ["id", "name", "age"])
        #expect(manager.primaryKeyColumns == ["id"])
        #expect(manager.rows.count == 3)
    }

    @Test("Selecting a WITHOUT ROWID table isolates primary keys")
    func selectingWithoutRowidTable() async throws {
        await manager.selectTable("tags")

        #expect(manager.selectedTableName == "tags")
        #expect(manager.primaryKeyColumns == ["name"])
        #expect(manager.rows.count == 2)
    }

    @Test("Filtering correctly subsets database queries")
    func filtering() async throws {
        await manager.selectTable("users")

        manager.filterText = "Alice"
        await manager.applyFilter()
        #expect(manager.rows.count == 1)
        #expect(manager.rows[0].data["name"] == "Alice")

        await manager.clearFilter()
        #expect(manager.filterText == "")
        #expect(manager.rows.count == 3)
    }

    @Test("Save active edits into valid SQL updates")
    func editingAndSaving() async throws {
        await manager.selectTable("users")

        let firstRowId = manager.rows[0].id
        manager.startEditing(rowID: firstRowId, column: "name", currentValue: "Alice")
        manager.updateActiveEdit(rowID: firstRowId, column: "name", value: "Alicia")
        manager.applyEdits()

        #expect(manager.hasChanges)
        #expect(manager.pendingChanges[firstRowId]?["name"] == "Alicia")

        await manager.saveChanges()

        #expect(!manager.hasChanges)

        let verifyQueue = try DatabaseQueue(path: dbURL.path)
        try await verifyQueue.read { db in
            let alicias = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM users WHERE name = 'Alicia'")
            #expect(alicias == 1)
        }
    }

    @Test("Executing a custom SQL query binds ad-hoc columns")
    func customSQLConsole() async throws {
        await manager.executeCustomSQL("SELECT name, age FROM users ORDER BY age DESC LIMIT 2")

        #expect(manager.selectedTableName == nil)
        #expect(manager.columns == ["name", "age"])
        #expect(manager.rows.count == 2)
        #expect(manager.rows[0].data["name"] == "Charlie")
        #expect(manager.rows[1].data["name"] == "Alice")
    }

    @Test("State resetting methods clear relevant properties")
    func stateResetting() async throws {
        await manager.selectTable("users")
        manager.updateCell(rowID: manager.rows[0].id, column: "name", value: "New Name")
        manager.startEditing(rowID: manager.rows[1].id, column: "name", currentValue: "Bob")
        manager.filterText = "Alice"

        #expect(!manager.pendingChanges.isEmpty)
        #expect(!manager.activeEdits.isEmpty)
        #expect(!manager.filterText.isEmpty)

        manager.discardChanges()
        #expect(manager.pendingChanges.isEmpty)

        manager.cancelEdits()
        #expect(manager.activeEdits.isEmpty)

        manager.filterText = ""
        await manager.applyFilter()
        #expect(manager.filterText == "")
    }
}
