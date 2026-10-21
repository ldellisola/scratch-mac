import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("Rendering"): the pieces of a fenced block that the styler works
/// from (the name on the fence, the lines of code, the fence lines) are found from the block's range and the text.
@MainActor
final class CodeBlockPartsTests: XCTestCase {
    private func parts(of block: String, in text: String) -> CodeBlockParts? {
        let nsText = text as NSString
        return CodeBlockParts(block: nsText.range(of: block), in: nsText)
    }

    private func substring(_ range: NSRange, of text: String) -> String {
        (text as NSString).substring(with: range)
    }

    func testAFencedBlockHasItsNameItsCodeAndItsFences() throws {
        let text = "intro\n```bash\n# note\nls -l\n```\nafter"
        let block = try XCTUnwrap(parts(of: "```bash\n# note\nls -l\n```", in: text))

        XCTAssertEqual(block.info, "bash")
        XCTAssertEqual(substring(block.content, of: text), "# note\nls -l")
        XCTAssertEqual(substring(block.closingLine, of: text), "```")
        XCTAssertEqual(substring(block.openingParagraph, of: text), "```bash\n")
        XCTAssertEqual(block.range, (text as NSString).range(of: "```bash\n# note\nls -l\n```"))
    }

    func testABlockWithoutLinesOfCodeHasNoContent() throws {
        let adjacent = "```\n```"
        XCTAssertEqual(parts(of: adjacent, in: adjacent)?.content, NSRange(location: 4, length: 0))
        XCTAssertEqual(parts(of: adjacent, in: adjacent)?.info, "")
        let blank = "```py\n\n```"
        XCTAssertEqual(parts(of: blank, in: blank)?.content, NSRange(location: 6, length: 0), "one empty line")
        XCTAssertEqual(parts(of: blank, in: blank)?.info, "py")
    }

    func testCRLFLinesAndSpacesAroundTheName() throws {
        let text = "  ```sql \r\nSELECT 1\r\nFROM t\r\n```"
        let block = try XCTUnwrap(parts(of: text, in: text))

        XCTAssertEqual(block.info, "sql")
        XCTAssertEqual(substring(block.content, of: text), "SELECT 1\r\nFROM t", "the last break is not code")
        XCTAssertEqual(substring(block.closingLine, of: text), "```")
    }

    func testTheNameOfAFenceLine() {
        XCTAssertEqual(CodeBlockParts.info(ofFenceLine: "```"), "")
        XCTAssertEqual(CodeBlockParts.info(ofFenceLine: "````swift"), "swift")
        XCTAssertEqual(CodeBlockParts.info(ofFenceLine: "``` C# "), "C#")
        XCTAssertEqual(CodeBlockParts.info(ofFenceLine: "```  "), "")
    }

    func testARangeThatIsNoBlockHasNoParts() {
        let text = "a\n```\nb\n```" as NSString
        XCTAssertNil(CodeBlockParts(block: NSRange(location: 0, length: 0), in: text))
        XCTAssertNil(CodeBlockParts(block: NSRange(location: 5, length: 100), in: text))
        XCTAssertNil(CodeBlockParts(block: NSRange(location: -1, length: 3), in: text))
    }
}
