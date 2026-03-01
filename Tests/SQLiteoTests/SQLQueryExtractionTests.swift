import Foundation
import Testing

@testable import SQLiteo

struct SQLQueryExtractionTests {
    @Test func testSelectionExactMatchIfRangeHasLength() {
        let sql = "SELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        let start = sql.index(sql.startIndex, offsetBy: 7)
        let end = sql.index(sql.startIndex, offsetBy: 12)
        let selection = start..<end

        let range = query.rangeToExecute(withSelection: selection)
        let extracted = String(sql[range])

        #expect(extracted == "* FRO")
    }

    @Test func testSingleQueryNoSemicolon() {
        let sql = "SELECT * FROM users"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)
        let selection = sql.startIndex..<sql.startIndex

        let range = query.rangeToExecute(withSelection: selection)
        let extracted = String(sql[range])

        #expect(extracted == "SELECT * FROM users")
    }

    @Test func testMultipleQueriesFirstSelected() {
        let sql = "SELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // Cursor at index 5 in the first query
        let cursor = sql.index(sql.startIndex, offsetBy: 5)
        let selection = cursor..<cursor

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM users")
    }

    @Test func testMultipleQueriesSecondSelected() {
        let sql = "SELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // Cursor at index 25 in the second query
        let cursor = sql.index(sql.startIndex, offsetBy: 25)
        let selection = cursor..<cursor

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM posts")
    }

    @Test func testMultipleQueriesMiddleSelected() {
        let sql = "SELECT * FROM a; SELECT * FROM b; SELECT * FROM c;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // Cursor at index 20 in the middle query
        let cursor = sql.index(sql.startIndex, offsetBy: 20)
        let selection = cursor..<cursor

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM b")
    }

    @Test func testCursorAfterLastSemicolon() {
        let sql = "SELECT * FROM users;\n\n"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)
        let cursor = sql.index(sql.startIndex, offsetBy: 21)  // In trailing newlines
        let selection = cursor..<cursor

        let range = query.rangeToExecute(withSelection: selection)
        let extracted = String(sql[range])
        #expect(extracted == "SELECT * FROM users;\n\n")
    }

    @Test func testCursorBeforeFirstQueryWithWhitespace() {
        let sql = "   \nSELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)
        let cursor = sql.index(sql.startIndex, offsetBy: 1)  // In prefix whitespaces
        let selection = cursor..<cursor

        let range = query.rangeToExecute(withSelection: selection)
        let extracted = String(sql[range])

        #expect(extracted == "SELECT * FROM users")
    }

    // MARK: - Stale Index Tests (crash fix)

    @Test func testStaleIndicesFromDifferentStringFallBackToFullSQL() {
        let oldSQL = "SELECT * FROM old_table WHERE id > 100"
        let newSQL = "SELECT 1"
        let query = SQLQuery(id: UUID(), name: "Test", sql: newSQL, isPersisted: false)

        // Indices from the old (longer) string
        let staleStart = oldSQL.index(oldSQL.startIndex, offsetBy: 10)
        let staleEnd = oldSQL.index(oldSQL.startIndex, offsetBy: 20)
        let staleSelection = staleStart..<staleEnd

        let range = query.rangeToExecute(withSelection: staleSelection)
        let extracted = String(newSQL[range])

        // Should fall back to full SQL since indices are out of bounds
        #expect(extracted == "SELECT 1")
    }

    @Test func testStaleIndicesFromEmptyStringFallBackToFullSQL() {
        let empty = ""
        let sql = "SELECT * FROM users"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // Indices from an empty string (simulating old initialization)
        let staleSelection = empty.startIndex..<empty.endIndex

        // This should not crash and should return something reasonable
        let range = query.rangeToExecute(withSelection: staleSelection)
        let extracted = String(sql[range])

        #expect(!extracted.isEmpty)
    }

    // MARK: - Cursor-at-start tests (simulating query switch)

    @Test func testCursorAtStartDetectsFirstStatement() {
        let sql = "SELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // After switching queries, cursor is reset to start of string
        let selection = sql.startIndex..<sql.startIndex

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM users")
    }

    @Test func testCursorAtStartSingleStatement() {
        let sql = "SELECT * FROM movie_movie;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        let selection = sql.startIndex..<sql.startIndex

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM movie_movie")
    }

    // MARK: - User selection tests

    @Test func testUserSelectionReturnsExactSelection() {
        let sql = "SELECT * FROM users; SELECT * FROM posts;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // User selects "SELECT * FROM posts"
        let start = sql.index(sql.startIndex, offsetBy: 21)
        let end = sql.index(sql.startIndex, offsetBy: 40)
        let selection = start..<end

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM posts")
    }

    @Test func testUserSelectionAcrossSemicolonPreserved() {
        let sql = "SELECT 1; SELECT 2; SELECT 3;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // User selects across multiple statements: "1; SELECT 2"
        let start = sql.index(sql.startIndex, offsetBy: 7)
        let end = sql.index(sql.startIndex, offsetBy: 18)
        let selection = start..<end

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "1; SELECT 2")
    }

    // MARK: - Edge cases

    @Test func testCursorAtEndOfSingleStatementNoSemicolon() {
        let sql = "SELECT * FROM movie_movie"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        let selection = sql.endIndex..<sql.endIndex

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]) == "SELECT * FROM movie_movie")
    }

    @Test func testCursorOnSemicolon() {
        let sql = "SELECT 1; SELECT 2;"
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)

        // Cursor right on the first semicolon
        let semiIndex = sql.firstIndex(of: ";")!
        let selection = semiIndex..<semiIndex

        let range = query.rangeToExecute(withSelection: selection)
        let extracted = String(sql[range])

        // Should detect the first statement (cursor is before/on the semicolon)
        #expect(extracted == "SELECT 1")
    }

    @Test func testEmptySQLReturnsEmptyRange() {
        let sql = ""
        let query = SQLQuery(id: UUID(), name: "Test", sql: sql, isPersisted: false)
        let selection = sql.startIndex..<sql.startIndex

        let range = query.rangeToExecute(withSelection: selection)
        #expect(String(sql[range]).isEmpty)
    }
}
