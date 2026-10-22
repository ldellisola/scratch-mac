import Foundation
import Testing

@testable import ScratchCode

// docs/decisions/0007-tree-sitter.md, "Packages": every grammar is a dependency pinned with `exact:` or is vendored into
// a C target of its own. Plan 5, task 3 vendored the SQL grammar, the last one that was pinned by a `revision:`.

/// `Packages/ScratchCode`, found from this file (`Tests/ScratchCodeTests/GrammarsTests.swift`).
private let packageDirectory: URL =
    URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func text(of path: String) -> String? {
    try? String(contentsOf: packageDirectory.appendingPathComponent(path), encoding: .utf8)
}

@Test func sqlBuildsFromVendoredSources() throws {
    let manifest = try #require(text(of: "Package.swift"))
    // No dependency is pinned with `revision:`, and none is the SQL grammar's package.
    #expect(!manifest.contains("revision:"), "Package.swift still pins a revision")
    let dependencies = manifest.split(separator: "\n").filter { $0.contains(".package(") || $0.contains("url:") }
    #expect(!dependencies.contains { $0.lowercased().contains("sql") }, "\(dependencies)")
    // The grammar is a C target of the package, with its licence and a README that says why.
    #expect(manifest.contains("name: \"GrammarSQL\""))
    #expect(manifest.contains("\"GrammarSQL\""))
    #expect(text(of: "Sources/GrammarSQL/LICENSE")?.contains("MIT License") == true)
    #expect(text(of: "Sources/GrammarSQL/README.md")?.contains("tree-sitter-sql") == true)
    #expect(text(of: "Sources/GrammarSQL/include/tree_sitter_sql.h")?.contains("tree_sitter_sql") == true)
    let parser = packageDirectory.appendingPathComponent("Sources/GrammarSQL/src/parser.c")
    #expect(FileManager.default.fileExists(atPath: parser.path))
    // And the vendored grammar is the one the highlighter uses.
    #expect(Grammar.grammar(for: .sql) != nil)
    let sql = "SELECT id, name FROM notes WHERE id = 1;\n"
    #expect(Highlighter.shared.errorRate(of: sql, language: .sql) == 0)
    #expect(Highlighter.shared.tokens(in: sql, language: .sql)?.isEmpty == false)
}
