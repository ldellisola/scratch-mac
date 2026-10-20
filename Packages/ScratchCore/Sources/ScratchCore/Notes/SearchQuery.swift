import Foundation

/// Turns what the owner typed in the sidebar's search field into an FTS5 `MATCH` expression (spec §6.2).
///
/// The text is never FTS5 syntax. Each word is quoted, so `"`, `*`, `-`, `(`, `NEAR`, `AND` and `OR` are only text, and
/// every word matches as a prefix, so the list narrows while the owner is still typing.
public enum SearchQuery {
    /// The expression for `text`, or nil when it has no word to look for.
    ///
    /// A word is a run of characters between whitespace. It counts when it has a letter or a digit in it, so
    /// `"-- ( *"` and `"😀"` are nothing, while `"-x"` is the word `x`. The words are all required (FTS5 reads a space
    /// as AND), in any order. A NUL character separates words too: FTS5 reads its expression as a C string, and a
    /// NUL would cut it short in the middle of a quote.
    public static func ftsExpression(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "\0" })
            .filter { word in word.contains { $0.isLetter || $0.isNumber } }
        guard !words.isEmpty else { return nil }
        return words.map { word in
            let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " ")
    }
}
