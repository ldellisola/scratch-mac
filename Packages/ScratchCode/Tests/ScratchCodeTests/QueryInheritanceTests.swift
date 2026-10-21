import Foundation
import Testing

@testable import ScratchCode

// Plan 4, task 3: "TypeScript's queries inherit JavaScript's, and C++'s inherit C's. The highlighter combines the
// parent's queries with the child's, so a `; inherits:` line is honoured whether the package resolves it or not."

/// Folders for `QueryInheritance.folders`, each with the text of its query.
private func resolve(_ roots: [String], _ queries: [String: String]) throws -> [String] {
    try QueryInheritance.folders(for: roots) { folder in
        guard let text = queries[folder] else { throw GrammarError.missingQueryFile(folder) }
        return text
    }
}

// MARK: The directive

@Test func theInheritsLineNamesTheParents() {
    let text = "; Highlights for TypeScript.\n; inherits: javascript\n\n(type_identifier) @type\n"
    #expect(QueryInheritance.parents(in: text) == ["javascript"])
}

@Test func severalParentsAndOptionalMarks() {
    #expect(QueryInheritance.parents(in: "; inherits: ecma,jsx\n(a) @b") == ["ecma", "jsx"])
    #expect(QueryInheritance.parents(in: ";; inherits: a, ?b ,c\n") == ["a", "b", "c"])
    #expect(QueryInheritance.parents(in: ";inherits:   c  \n") == ["c"])
}

@Test func noDirectiveNoParents() {
    #expect(QueryInheritance.parents(in: "") == [])
    #expect(QueryInheritance.parents(in: "(identifier) @variable\n") == [])
    #expect(QueryInheritance.parents(in: "; just a comment\n\n; inherits-from: c\n(a) @b\n") == [])
    #expect(QueryInheritance.parents(in: "; inherits:\n(a) @b\n") == [])
}

@Test func onlyTheLeadingCommentsAreRead() {
    // Below the first pattern, `; inherits: c` is an ordinary comment.
    #expect(QueryInheritance.parents(in: "(a) @b\n; inherits: c\n") == [])
    #expect(QueryInheritance.parents(in: "; one\n\n  ; inherits: c\n(a) @b\n; inherits: d\n") == ["c"])
}

// MARK: The order

@Test func aFolderWithoutParentsIsAlone() throws {
    #expect(try resolve(["swift"], ["swift": "(a) @b"]) == ["swift"])
}

@Test func parentsComeBeforeTheirChildren() throws {
    let queries = ["ts": "; inherits: js\n(a) @b", "js": "(c) @d"]
    #expect(try resolve(["ts"], queries) == ["js", "ts"])
    // Through two levels, and with the parents of one folder in the order they were named.
    let deep = ["a": "; inherits: b, c\n", "b": "; inherits: d\n", "c": "", "d": ""]
    #expect(try resolve(["a"], deep) == ["d", "b", "c", "a"])
}

@Test func aFolderIsReadOnceWhoeverInheritsIt() throws {
    let queries = ["a": "; inherits: c\n", "b": "; inherits: c\n", "c": ""]
    #expect(try resolve(["a", "b"], queries) == ["c", "a", "b"])
    // A root that is also a parent.
    #expect(try resolve(["c", "a"], queries) == ["c", "a"])
}

@Test func aCycleDoesNotLoop() throws {
    let queries = ["a": "; inherits: b\n", "b": "; inherits: a\n"]
    #expect(try resolve(["a"], queries) == ["b", "a"])
    #expect(try resolve(["x"], ["x": "; inherits: x\n"]) == ["x"])
}

@Test func aMissingParentIsAnError() {
    #expect(throws: GrammarError.self) { try resolve(["a"], ["a": "; inherits: nowhere\n"]) }
    #expect(throws: GrammarError.self) { try resolve(["gone"], [:]) }
}

// MARK: What the package ships

@Test func typescriptAndCppInheritFromTheirParents() throws {
    func folders(_ language: CodeLanguage) throws -> [String] {
        let grammar = try #require(Grammar.grammar(for: language))
        return try QueryInheritance.folders(for: grammar.queryFolders, source: Grammar.queryText(in:))
    }
    #expect(try folders(.typescript) == ["javascript", "typescript"])
    #expect(try folders(.cpp) == ["c", "cpp"])
    #expect(try folders(.javascript) == ["javascript", "javascript-jsx"])
    #expect(try folders(.c) == ["c"])
    #expect(try folders(.swift) == ["swift"])
}

@Test func everyLanguageHasAGrammarAndItsQueryFiles() throws {
    for language in CodeLanguage.allCases {
        let grammar = try #require(Grammar.grammar(for: language), "no grammar for \(language.fenceName)")
        let folders = try QueryInheritance.folders(for: grammar.queryFolders, source: Grammar.queryText(in:))
        #expect(!folders.isEmpty)
        // The query compiles for the grammar: a node or field name that the grammar does not have is an error.
        _ = try grammar.makeQuery()
    }
}

@Test func everyQueryFolderBelongsToALanguage() throws {
    // The folders in the source tree (this file is Tests/ScratchCodeTests/QueryInheritanceTests.swift).
    let queries = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/ScratchCode/Queries")
    let onDisk = try FileManager.default.contentsOfDirectory(atPath: queries.path)
    var used: Set<String> = []
    for language in CodeLanguage.allCases {
        let grammar = try #require(Grammar.grammar(for: language))
        used.formUnion(try QueryInheritance.folders(for: grammar.queryFolders, source: Grammar.queryText(in:)))
    }
    #expect(Set(onDisk) == used)
}
