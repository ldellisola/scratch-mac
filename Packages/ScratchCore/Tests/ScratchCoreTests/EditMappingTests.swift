import Foundation
import Testing

@testable import ScratchCore

// Plan 3, task 3: ranges kept from before an edit (fenced blocks, the paragraphs still to be styled) are carried over
// it, so that the editor never scans or restyles the whole note for one keystroke.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

@Test func anInsertionBeforeARangeMovesIt() {
    let edit = EditMapping(replaced: r(10, 0), newLength: 3)
    #expect(edit.delta == 3)
    #expect(edit.mapped(r(20, 5)) == r(23, 5))
}

@Test func aDeletionBeforeARangeMovesIt() {
    let edit = EditMapping(replaced: r(10, 4), newLength: 0)
    #expect(edit.delta == -4)
    #expect(edit.mapped(r(20, 5)) == r(16, 5))
}

@Test func anEditAfterARangeLeavesIt() {
    let edit = EditMapping(replaced: r(30, 2), newLength: 9)
    #expect(edit.mapped(r(20, 5)) == r(20, 5))
}

@Test func anEditInsideARangeResizesIt() {
    #expect(EditMapping(replaced: r(22, 0), newLength: 4).mapped(r(20, 10)) == r(20, 14))
    #expect(EditMapping(replaced: r(22, 3), newLength: 0).mapped(r(20, 10)) == r(20, 7))
    #expect(EditMapping(replaced: r(22, 3), newLength: 1).mapped(r(20, 10)) == r(20, 8))
}

@Test func anInsertionAtTheEndOfARangeStaysOutsideIt() {
    #expect(EditMapping(replaced: r(30, 0), newLength: 4).mapped(r(20, 10)) == r(20, 10))
}

@Test func anInsertionAtTheStartOfARangeIsInsideIt() {
    #expect(EditMapping(replaced: r(20, 0), newLength: 4).mapped(r(20, 10)) == r(20, 14))
}

@Test func anEditThatOverlapsTheStartTakesInTheNewText() {
    // 15..<25 is replaced by 2 units: the range 20..<30 now starts at the new text (15..<17) and ends with what was
    // after it (25..<30 is now 17..<22).
    #expect(EditMapping(replaced: r(15, 10), newLength: 2).mapped(r(20, 10)) == r(15, 7))
}

@Test func anEditThatOverlapsTheEndTakesInTheNewText() {
    #expect(EditMapping(replaced: r(25, 10), newLength: 2).mapped(r(20, 10)) == r(20, 7))
}

@Test func anEditThatSwallowsARangeEmptiesIt() {
    #expect(EditMapping(replaced: r(15, 30), newLength: 0).mapped(r(20, 10)).length == 0)
}

@Test func theMappingFromAStorageReportCoversTheEditedRange() {
    // `didProcessEditing` reports the range of the new text and the change in length: 3 units typed over nothing.
    let typed = EditMapping(editedRange: r(10, 3), changeInLength: 3)
    #expect(typed == EditMapping(replaced: r(10, 0), newLength: 3))
    // 2 units replaced 5.
    let replaced = EditMapping(editedRange: r(10, 2), changeInLength: -3)
    #expect(replaced == EditMapping(replaced: r(10, 5), newLength: 2))
    // 4 units deleted.
    let deleted = EditMapping(editedRange: r(10, 0), changeInLength: -4)
    #expect(deleted == EditMapping(replaced: r(10, 4), newLength: 0))
}

@Test func aNegativeReplacedLengthIsClampedToZero() {
    let edit = EditMapping(editedRange: r(10, 2), changeInLength: 5)
    #expect(edit.replaced == r(10, 0))
}
