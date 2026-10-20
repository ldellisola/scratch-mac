import Foundation

/// One value in a SQLite column, in SQLite's own five storage classes.
public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
}

extension SQLValue {
    /// A date stored as a REAL holding `timeIntervalSinceReferenceDate`. It reads back exactly.
    public static func date(_ d: Date) -> SQLValue {
        .real(d.timeIntervalSinceReferenceDate)
    }

    /// Like ``date(_:)``, with `nil` stored as NULL.
    public static func optionalDate(_ d: Date?) -> SQLValue {
        d.map(SQLValue.date) ?? .null
    }
}

/// One result row. Columns are looked up by name. When a query returns the same name twice, the first one wins.
///
/// SQLite is dynamically typed, so each typed accessor returns `nil` unless the stored value has that type.
public struct Row: Sendable {
    private let columns: [String: Int]
    private let values: [SQLValue]

    /// `columns` maps each column name to its index in `values`. Every row of one query shares the same map.
    init(columns: [String: Int], values: [SQLValue]) {
        self.columns = columns
        self.values = values
    }

    /// The raw value, which is `.null` for a NULL column, or `nil` when the row has no such column.
    public subscript(_ column: String) -> SQLValue? {
        columns[column].map { values[$0] }
    }

    public func string(_ c: String) -> String? {
        if case .text(let value)? = self[c] { return value }
        return nil
    }

    public func int(_ c: String) -> Int64? {
        if case .integer(let value)? = self[c] { return value }
        return nil
    }

    /// A REAL value, or an INTEGER converted to `Double`.
    public func double(_ c: String) -> Double? {
        switch self[c] {
        case .real(let value)?: return value
        case .integer(let value)?: return Double(value)
        default: return nil
        }
    }

    /// A date stored by ``SQLValue/date(_:)``: a REAL holding `timeIntervalSinceReferenceDate`.
    public func date(_ c: String) -> Date? {
        double(c).map { Date(timeIntervalSinceReferenceDate: $0) }
    }
}
