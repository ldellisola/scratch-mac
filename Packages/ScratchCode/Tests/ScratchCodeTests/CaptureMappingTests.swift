import Testing

@testable import ScratchCode

// Plan 4, "Tree-sitter capture names map to kinds by prefix".

private func kind(_ name: String, _ language: CodeLanguage = .swift) -> HighlightKind? {
    CaptureMapping.kind(forCapture: name, language: language)
}

@Test func commentsAndStrings() {
    #expect(kind("comment") == .comment)
    #expect(kind("comment.documentation") == .comment)
    #expect(kind("string") == .string)
    #expect(kind("string.escape") == .string)
    #expect(kind("string.regexp") == .string)
    #expect(kind("character") == .string)
}

@Test func numbers() {
    #expect(kind("number") == .number)
    #expect(kind("number.float") == .number)
    #expect(kind("float") == .number)
    #expect(kind("constant.numeric") == .number)
}

@Test func keywords() {
    for name in [
        "keyword", "keyword.function", "keyword.return", "keyword.import", "boolean", "constant.builtin",
        "conditional", "repeat", "exception", "tag",
    ] {
        #expect(kind(name) == .keyword, "\(name)")
    }
}

@Test func typesFunctionsAttributes() {
    #expect(kind("type") == .type)
    #expect(kind("type.builtin") == .type)
    #expect(kind("constructor") == .type)
    #expect(kind("function") == .function)
    #expect(kind("function.method") == .function)
    #expect(kind("function.call") == .function)
    #expect(kind("method") == .function)
    #expect(kind("attribute") == .attribute)
    #expect(kind("decorator") == .attribute)
    #expect(kind("annotation") == .attribute)
}

@Test func includeIsAPreprocessorDirectiveInCAndCpp() {
    #expect(kind("include", .swift) == .keyword)
    #expect(kind("include", .python) == .keyword)
    #expect(kind("include", .c) == .preprocessor)
    #expect(kind("include", .cpp) == .preprocessor)
    #expect(kind("preproc") == .preprocessor)
    #expect(kind("preproc.define", .c) == .preprocessor)
}

@Test func everythingElseIsTheTextColour() {
    for name in [
        "variable", "variable.parameter", "variable.builtin", "property", "operator", "punctuation.bracket",
        "punctuation.delimiter", "punctuation.special", "label", "spell", "embedded", "escape", "constant",
        "constant.macro", "character.special", "module", "namespace",
    ] {
        #expect(kind(name) == nil, "\(name)")
    }
}

@Test func aPrefixNeedsAWholeWord() {
    // `typeface` is not `type`, and `keywords` is not `keyword`.
    #expect(kind("typeface") == nil)
    #expect(kind("keywords") == nil)
    #expect(kind("functional") == nil)
    #expect(kind("") == nil)
}
