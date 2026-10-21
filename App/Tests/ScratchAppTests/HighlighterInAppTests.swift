import ScratchCode
import XCTest

/// Hosted in the app: `ScratchCode` (tree-sitter, Plan 4 task 2) works inside the real app, where its highlight queries
/// are a resource bundle in `Scratch.app/Contents/Resources` and the grammars are linked in. Under `swift test` the
/// package is tested on its own (Packages/ScratchCode/Tests); what only the app can show is that Xcode ships the
/// bundle and that `Bundle.module` finds it there, and not only in the build folder. docs/decisions/0007-tree-sitter.md.
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
        XCTAssertTrue(queries.contains { $0.hasSuffix("Queries/swift/highlights.scm") }, "\(queries)")
        XCTAssertTrue(queries.contains { $0.hasSuffix("Queries/python/highlights.scm") }, "\(queries)")
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
