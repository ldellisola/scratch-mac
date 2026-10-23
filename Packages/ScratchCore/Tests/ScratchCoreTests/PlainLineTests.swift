import Foundation
import Testing

@testable import ScratchCore

// Plan 6, Task 4 (docs/features/sidebar.md, "A row shows text without markers"): a sidebar row and a tab show a line as
// the editor shows it outside a fenced block, so `PlainLine.text(of:)` takes out what the editor hides: a bullet's
// `- ` and a checkbox's `[?] ` with the indent before them, the `**` of a bold run and the backticks of inline code.
// A link stays as typed, and so does everything the parser does not make a span of (docs/decisions/0006).

private func plain(_ line: String) -> String { String(PlainLine.text(of: line[...])) }

// MARK: Lists

@Test func aBulletLosesItsDashAndItsIndent() {
    #expect(plain("- check error rate") == "check error rate")
    #expect(plain("  - nested bullet") == "nested bullet")
    #expect(plain("      - deeper") == "deeper")
}

@Test func aCheckboxLosesItsBoxAndItsIndent() {
    #expect(plain("[ ] open task") == "open task")
    #expect(plain("[x] done task") == "done task")
    #expect(plain("[X] done task") == "done task")
    #expect(plain("    [ ] nested task") == "nested task")
}

@Test func aBoxInsideABulletIsText() {
    // "`- [ ] a` is a bullet, not a checkbox" (MarkupParser): the editor shows the box's characters.
    #expect(plain("- [ ] a") == "[ ] a")
}

@Test func aDashOrABracketThatIsNoMarkerStaysAsTyped() {
    #expect(plain("-5 degrees") == "-5 degrees")
    #expect(plain("-") == "-")
    #expect(plain("[ ]") == "[ ]")
    #expect(plain("[ ]x") == "[ ]x")
    #expect(plain("[?] not a box") == "[?] not a box")
    #expect(plain("\t- tab, not spaces") == "\t- tab, not spaces")
    #expect(plain("1. numbered") == "1. numbered")
}

// MARK: Bold and inline code

@Test func boldLosesItsStars() {
    #expect(plain("**don't** deploy") == "don't deploy")
    #expect(plain("run **the** tests, **then** ship") == "run the tests, then ship")
}

@Test func inlineCodeLosesItsBackticksAndKeepsWhatIsInside() {
    #expect(plain("bump to `2.4.1`") == "bump to 2.4.1")
    #expect(plain("`inline **code**` stays literal") == "inline **code** stays literal")
}

@Test func boldAroundCodeLosesBothKindsOfMarkers() {
    #expect(plain("**`x`**") == "x")
    #expect(plain("see **the `init()` call**") == "see the init() call")
}

@Test func aListMarkerAndInlineMarkersGoTogether() {
    #expect(plain("- **don't** deploy") == "don't deploy")
    #expect(plain("[ ] bump version to `2.4.1`") == "bump version to 2.4.1")
    #expect(plain("  [x] **ship** it") == "ship it")
}

@Test func globsAndOperatorsAreNotBold() {
    // ADR 0006: the stars need word boundaries, so these are text and stay.
    #expect(plain("src/**/*.ts") == "src/**/*.ts")
    #expect(plain("x**2 + y**2") == "x**2 + y**2")
    #expect(plain("a**b**c") == "a**b**c")
    #expect(plain("(a)**(b)") == "(a)**(b)")
}

@Test func unclosedMarkersStayAsTyped() {
    #expect(plain("Unclosed **star and a lone ` tick stay plain.") == "Unclosed **star and a lone ` tick stay plain.")
    #expect(plain("two `` backticks") == "two `` backticks")
}

// MARK: Links and everything else

@Test func aLinkIsKeptAsTyped() {
    #expect(plain("see https://example.com/a_(b)?q=1.") == "see https://example.com/a_(b)?q=1.")
    #expect(plain("- https://example.com") == "https://example.com")
    #expect(plain("**https://example.com**") == "https://example.com")
}

@Test func textWithNothingToTakeOutIsTheSameSubstring() {
    let line = "  just words, no markers"[...]
    let result = PlainLine.text(of: line)
    #expect(result == line)
    #expect(result.startIndex == line.startIndex && result.endIndex == line.endIndex)
}

@Test func unicodeSurvivesTheEdit() {
    #expect(plain("[ ] café **naïve** 😀 `日本`") == "café naïve 😀 日本")
    #expect(plain("**😀**") == "😀")
    #expect(plain("e\u{301} **a**") == "e\u{301} a")
}

@Test func aSubstringOfALongerStringIsJudgedByItself() {
    let text = "first\n- second\nthird"
    let line = text[text.index(text.startIndex, offsetBy: 6)..<text.index(text.startIndex, offsetBy: 14)]
    #expect(line == "- second")
    #expect(String(PlainLine.text(of: line)) == "second")
}

// MARK: Only markers

@Test func aLineThatIsOnlyMarkersHasNoText() {
    #expect(plain("- ") == "")
    #expect(plain("  - ") == "")
    #expect(plain("[ ] ") == "")
    #expect(plain("[x] ") == "")
    // The empty pair that ⌘B on a caret makes (plan 6 task 5) is markers only, with or without a list marker.
    #expect(plain("****") == "")
    #expect(plain("- ****") == "")
    #expect(plain("[ ] ****") == "")
    #expect(plain("  ****  ") == "")
}

@Test func starsWithWordsAroundThemAreStillText() {
    #expect(plain("**** hello") == "**** hello")
    #expect(plain("hello ****") == "hello ****")
    #expect(plain("*****") == "*****")
}
