import ScratchCode
import XCTest

/// Hosted in the app: `ScratchCode` (tree-sitter, Plan 4 tasks 2 and 3) works inside the real app, where its highlight
/// queries are a resource bundle in `Scratch.app/Contents/Resources` and the seventeen grammars are linked in. Under
/// `swift test` the package is tested on its own (Packages/ScratchCode/Tests); what only the app can show is that Xcode
/// ships the bundle and that `Bundle.module` finds it there, and not only in the build folder, and that every grammar
/// links and parses in the app. docs/decisions/0007-tree-sitter.md.
final class HighlighterInAppTests: XCTestCase {
    private func token(_ location: Int, _ length: Int, _ kind: HighlightKind) -> HighlightToken {
        HighlightToken(range: NSRange(location: location, length: length), kind: kind)
    }

    func testTheAppCarriesTheQueriesBundle() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let bundle = resources.appendingPathComponent("ScratchCode_ScratchCode.bundle")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bundle.path), "\(bundle.path) is not in the app")
        let queries = FileManager.default.enumerator(atPath: bundle.path)?.allObjects as? [String] ?? []
        // The queries of the seventeen languages, and `javascript-jsx`, JavaScript's JSX addition, a folder of its own
        // (TypeScript and C++ build on the queries of JavaScript and C, which are folders already).
        let folders = CodeLanguage.allCases.map(\.fenceName) + ["javascript-jsx"]
        for folder in folders {
            XCTAssertTrue(
                queries.contains { $0.hasSuffix("Queries/\(folder)/highlights.scm") },
                "no Queries/\(folder)/highlights.scm in the bundle: \(queries)")
        }
    }

    /// A short text for each language that its grammar parses and its query colours with the given kind.
    private let snippets: [(CodeLanguage, String, HighlightKind)] = [
        (.swift, "let a = 1 // one", .keyword),
        (.python, "def f():\n    return 1\n", .keyword),
        (.javascript, "const a = 1 // one", .keyword),
        (.typescript, "interface A { b: string }\n", .keyword),
        (.json, "{\"a\": true}", .string),
        (.bash, "if true; then echo hi; fi\n", .keyword),
        (.sql, "SELECT 1 FROM t;", .keyword),
        (.yaml, "a: \"b\"\n", .string),
        (.html, "<p>hi</p>\n", .keyword),
        (.css, "a { color: red; }\n@media x { }\n", .keyword),
        (.csharp, "public class A { }\n", .keyword),
        (.go, "func main() { }\n", .keyword),
        (.rust, "fn main() { }\n", .keyword),
        (.c, "#include <x>\nint a;\n", .preprocessor),
        (.cpp, "#include <x>\nclass A { };\n", .preprocessor),
        (.java, "public class A { }\n", .keyword),
        (.powershell, "function F { return 1 }\n", .keyword),
    ]

    func testEveryLanguageIsColouredInTheApp() {
        XCTAssertEqual(Set(snippets.map { $0.0 }), Set(CodeLanguage.allCases))
        for (language, text, kind) in snippets {
            let tokens = Highlighter.shared.tokens(in: text, language: language) ?? []
            XCTAssertTrue(
                tokens.contains { $0.kind == kind }, "\(language.fenceName) has no \(kind) token in \(tokens)")
            XCTAssertLessThan(Highlighter.shared.errorRate(of: text, language: language), 0.05, language.fenceName)
        }
    }

    func testSwiftIsColouredInTheApp() {
        let tokens = Highlighter.shared.tokens(in: #"let s = "hi" // note"#, language: .swift)
        XCTAssertEqual(tokens, [token(0, 3, .keyword), token(8, 4, .string), token(13, 7, .comment)])
    }

    func testPythonIsColouredInTheApp() {
        let tokens = Highlighter.shared.tokens(in: "@app.route(\"/\")\ndef index():\n    return 1\n", language: .python)
        XCTAssertEqual(tokens?.first, token(0, 10, .attribute))
        XCTAssertEqual(tokens?.contains(token(11, 3, .string)), true)
        XCTAssertEqual(tokens?.contains(token(16, 3, .keyword)), true)
    }

    func testHighlightingWorksOffTheMainThread() async {
        // The app highlights on a background queue, so the highlighter must not need the main thread.
        let result = await Task.detached { () -> ([HighlightToken]?, Double) in
            (
                Highlighter.shared.tokens(in: "let a = 1 // one", language: .swift),
                Highlighter.shared.errorRate(of: "let a = 1\n", language: .swift)
            )
        }.value
        XCTAssertEqual(result.0?.count, 3)
        XCTAssertEqual(result.1, 0)
    }
}
