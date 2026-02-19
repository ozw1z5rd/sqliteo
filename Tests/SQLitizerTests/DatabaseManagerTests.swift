import XCTest
import GRDB
@testable import SQLitizer

final class DatabaseManagerTests: XCTestCase {
    func testListTables() throws {
        let manager = DatabaseManager()
        let dbQueue = try DatabaseQueue() // In-memory
        
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
            try db.execute(sql: "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)")
        }
        
        manager.dbQueue = dbQueue
        try manager.fetchTables()
        
        XCTAssertTrue(manager.tableNames.contains("users"))
        XCTAssertTrue(manager.tableNames.contains("posts"))
    }
}
