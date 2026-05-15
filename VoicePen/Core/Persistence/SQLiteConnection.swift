import Foundation
import SQLite3

nonisolated enum SQLiteStep: Equatable {
    case row
    case done
}

nonisolated final class SQLiteConnection {
    private let database: OpaquePointer
    private let makeError: (String) -> Error

    var rawDatabase: OpaquePointer {
        database
    }

    private init(database: OpaquePointer, makeError: @escaping (String) -> Error) {
        self.database = database
        self.makeError = makeError
    }

    deinit {
        sqlite3_close(database)
    }

    static func open(
        at databaseURL: URL,
        fileManager: FileManager = .default,
        makeError: @escaping (String) -> Error
    ) throws -> SQLiteConnection {
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw makeError(message)
        }

        return SQLiteConnection(database: database, makeError: makeError)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError()
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        return SQLiteStatement(statement: statement, connection: self)
    }

    func sqliteError() -> Error {
        makeError(String(cString: sqlite3_errmsg(database)))
    }
}

nonisolated final class SQLiteStatement {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let statement: OpaquePointer
    private let connection: SQLiteConnection

    init(statement: OpaquePointer, connection: SQLiteConnection) {
        self.statement = statement
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func step() throws -> SQLiteStep {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return .row
        case SQLITE_DONE:
            return .done
        default:
            throw connection.sqliteError()
        }
    }

    func stepDone() throws {
        guard try step() == .done else {
            throw connection.sqliteError()
        }
    }

    func bindText(_ value: String, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    func bindDouble(_ value: Double, at index: Int32) {
        sqlite3_bind_double(statement, index, value)
    }

    func bindInt(_ value: Int32, at index: Int32) {
        sqlite3_bind_int(statement, index, value)
    }

    func bindInt64(_ value: Int64, at index: Int32) {
        sqlite3_bind_int64(statement, index, value)
    }

    func bindNull(at index: Int32) {
        sqlite3_bind_null(statement, index)
    }

    func bindBlob(_ data: Data, at index: Int32) {
        guard !data.isEmpty else {
            sqlite3_bind_zeroblob(statement, index, 0)
            return
        }

        _ = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), Self.sqliteTransient)
        }
    }

    func string(at index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    func optionalString(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return string(at: index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func optionalDouble(at index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return double(at: index)
    }

    func int(at index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func optionalInt(at index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(int64(at: index))
    }

    func optionalData(at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: byteCount)
    }
}
