/// Tree-sitter capture names (`@keyword.function`, `@string.escape`) to the eight kinds Scratch colours, by prefix
/// (Plan 4 "Colours"). A name with no kind, such as `@variable` or `@punctuation.bracket`, gives nil: that text keeps
/// the text colour.
enum CaptureMapping {
    static func kind(forCapture name: String, language: CodeLanguage) -> HighlightKind? {
        // `include` is a keyword in most languages and a preprocessor directive in C and C++.
        if matches(name, "include") {
            return language == .c || language == .cpp ? .preprocessor : .keyword
        }
        // `@character.special` marks things such as a wildcard `_`, which are not text in quotes.
        if matches(name, "character.special") {
            return nil
        }
        for (prefix, kind) in table where matches(name, prefix) {
            return kind
        }
        return nil
    }

    /// Whether `name` is `prefix` or starts with `prefix` and a dot.
    private static func matches(_ name: String, _ prefix: String) -> Bool {
        name == prefix || name.hasPrefix(prefix + ".")
    }

    private static let table: [(prefix: String, kind: HighlightKind)] = [
        ("comment", .comment),
        ("string", .string),
        ("character", .string),
        ("number", .number),
        ("float", .number),
        ("constant.numeric", .number),
        ("keyword", .keyword),
        ("boolean", .keyword),
        ("constant.builtin", .keyword),
        ("conditional", .keyword),
        ("repeat", .keyword),
        ("exception", .keyword),
        ("tag", .keyword),
        ("type", .type),
        ("constructor", .type),
        ("function", .function),
        ("method", .function),
        ("attribute", .attribute),
        ("decorator", .attribute),
        ("annotation", .attribute),
        ("preproc", .preprocessor),
    ]
}
