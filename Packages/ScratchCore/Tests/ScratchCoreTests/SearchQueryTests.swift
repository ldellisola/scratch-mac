import Testing

@testable import ScratchCore

// Spec §6.2: the sidebar search matches titles and note text. `SearchQuery` turns what the owner typed into an FTS5
// MATCH expression that matches the words literally, so no input is ever FTS5 syntax.

@Test func quotesEachTokenAsPrefix() { #expect(SearchQuery.ftsExpression("kube roll") == #""kube"* "roll"*"#) }

@Test func doublesInnerQuotes() { #expect(SearchQuery.ftsExpression(#"say"hi"#) == #""say""hi"*"#) }

@Test func dropsTokensWithoutLettersOrDigits() { #expect(SearchQuery.ftsExpression("-- * ( ) \"") == nil) }

@Test func blankIsNil() {
    #expect(SearchQuery.ftsExpression("") == nil)
    #expect(SearchQuery.ftsExpression("   ") == nil)
    #expect(SearchQuery.ftsExpression("\t\n") == nil)
}

@Test func keepsPunctuationInsideATokenThatHasALetter() {
    #expect(SearchQuery.ftsExpression("-x (a") == #""-x"* "(a"*"#)
}

@Test func splitsOnAnyWhitespaceAndIgnoresExtraSpaces() {
    #expect(SearchQuery.ftsExpression("  a \t b\r\n\nc ") == #""a"* "b"* "c"*"#)
}

@Test func keepsDigitsAndNonLatinLetters() {
    #expect(SearchQuery.ftsExpression("2025 café 日本") == #""2025"* "café"* "日本"*"#)
}

@Test func dropsEmojiOnlyTokens() {
    #expect(SearchQuery.ftsExpression("😀") == nil)
    #expect(SearchQuery.ftsExpression("😀 ok") == #""ok"*"#)
}

@Test func keywordsAreQuotedSoTheyStayWords() {
    #expect(SearchQuery.ftsExpression("a AND NEAR OR") == #""a"* "AND"* "NEAR"* "OR"*"#)
}

@Test func aNulCharacterSeparatesTokens() {
    // FTS5 reads its expression as a C string, so a NUL would cut the expression short and leave a quote open.
    #expect(SearchQuery.ftsExpression("a\u{0}b") == #""a"* "b"*"#)
}
