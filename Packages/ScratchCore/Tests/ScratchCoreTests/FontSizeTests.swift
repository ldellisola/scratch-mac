import Testing

@testable import ScratchCore

// Spec §6.4: ⌘+ / ⌘− / ⌘0 change the font size for all notes: 13 pt by default, 9 to 32 pt in 1 pt steps.

@Test func standardMinimumAndMaximum() {
    #expect(FontSize.standard == 13)
    #expect(FontSize.minimum == 9)
    #expect(FontSize.maximum == 32)
}

@Test func largerAddsOnePoint() {
    #expect(FontSize.larger(13) == 14)
    #expect(FontSize.larger(9) == 10)
}

@Test func smallerSubtractsOnePoint() {
    #expect(FontSize.smaller(13) == 12)
    #expect(FontSize.smaller(32) == 31)
}

@Test func largerStopsAt32() {
    #expect(FontSize.larger(31) == 32)
    #expect(FontSize.larger(32) == 32)
    #expect(FontSize.larger(31.5) == 32)
}

@Test func smallerStopsAt9() {
    #expect(FontSize.smaller(10) == 9)
    #expect(FontSize.smaller(9) == 9)
    #expect(FontSize.smaller(9.5) == 9)
}

@Test func steppingFromTheStandardSizeReachesEachEnd() {
    var size = FontSize.standard
    for _ in 0..<100 { size = FontSize.larger(size) }
    #expect(size == 32)
    for _ in 0..<100 { size = FontSize.smaller(size) }
    #expect(size == 9)
}

@Test func clampedKeepsASizeInRange() {
    #expect(FontSize.clamped(9) == 9)
    #expect(FontSize.clamped(16) == 16)
    #expect(FontSize.clamped(32) == 32)
    #expect(FontSize.clamped(13.5) == 13.5)
}

@Test func clampedPullsASizeIntoRange() {
    #expect(FontSize.clamped(8.99) == 9)
    #expect(FontSize.clamped(0) == 9)
    #expect(FontSize.clamped(-5) == 9)
    #expect(FontSize.clamped(32.01) == 32)
    #expect(FontSize.clamped(500) == 32)
}

@Test func clampedHandlesInfinity() {
    #expect(FontSize.clamped(.infinity) == 32)
    #expect(FontSize.clamped(-.infinity) == 9)
}

@Test func clampedHandlesNaN() {
    #expect(FontSize.clamped(.nan) == 13)
    #expect(FontSize.larger(.nan) == 13)
    #expect(FontSize.smaller(.nan) == 13)
}
