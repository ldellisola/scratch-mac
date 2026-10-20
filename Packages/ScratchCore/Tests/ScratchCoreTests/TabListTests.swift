import Testing

@testable import ScratchCore

// Spec §6.3: tabs are views onto notes. There is always at least one tab, and a note that is already open in a tab is
// focused instead of opened a second time. Closing a tab never deletes its note.

private func note(_ name: String) -> NoteID { NoteID(rawValue: name) }

private func tab(_ name: String, selection: Int = 0, scrollY: Double = 0, scrollAnchor: Int? = nil) -> TabState {
    TabState(noteID: note(name), selection: selection, scrollY: scrollY, scrollAnchor: scrollAnchor)
}

/// A list of tabs showing the notes `names`, with the tab at `active` selected.
private func list(_ names: [String], active: Int = 0) -> TabList {
    TabList(tabs: names.map { tab($0) }, activeIndex: active)
}

private func names(_ list: TabList) -> [String] { list.tabs.map(\.noteID.rawValue) }

// MARK: open

@Test func openFocusesExistingTab() {
    var tabs = list(["A", "B", "C"], active: 0)
    #expect(tabs.open(note("C"), inNewTab: false) == .focused(index: 2))
    #expect(names(tabs) == ["A", "B", "C"])
    #expect(tabs.activeIndex == 2)
}

@Test func openFocusesExistingTabEvenInANewTab() {
    var tabs = list(["A", "B", "C"], active: 2)
    #expect(tabs.open(note("A"), inNewTab: true) == .focused(index: 0))
    #expect(names(tabs) == ["A", "B", "C"])
    #expect(tabs.activeIndex == 0)
}

@Test func openFocusingTheActiveTabChangesNothing() {
    var tabs = list(["A", "B"], active: 1)
    let before = tabs
    #expect(tabs.open(note("B"), inNewTab: false) == .focused(index: 1))
    #expect(tabs == before)
}

@Test func openFocusingATabKeepsItsViewState() {
    var tabs = TabList(tabs: [tab("A", selection: 7, scrollAnchor: 40), tab("B")], activeIndex: 1)
    _ = tabs.open(note("A"), inNewTab: false)
    #expect(tabs.active == tab("A", selection: 7, scrollAnchor: 40))
}

@Test func openInNewTabInsertsAfterActive() {
    var tabs = list(["A", "B", "C"], active: 1)
    #expect(tabs.open(note("D"), inNewTab: true) == .inserted(index: 2))
    #expect(names(tabs) == ["A", "B", "D", "C"])
    #expect(tabs.activeIndex == 2)
    #expect(tabs.active == tab("D"))
}

@Test func openInNewTabAfterTheLastTabAppends() {
    var tabs = list(["A", "B"], active: 1)
    #expect(tabs.open(note("C"), inNewTab: true) == .inserted(index: 2))
    #expect(names(tabs) == ["A", "B", "C"])
    #expect(tabs.activeIndex == 2)
}

@Test func openReplacesActiveNote() {
    var tabs = list(["A", "B", "C"], active: 1)
    #expect(tabs.open(note("D"), inNewTab: false) == .replaced(index: 1, previous: note("B")))
    #expect(names(tabs) == ["A", "D", "C"])
    #expect(tabs.activeIndex == 1)
}

@Test func openReplacingStartsTheNewNoteAtTheTop() {
    var tabs = TabList(tabs: [tab("A", selection: 9, scrollY: 120, scrollAnchor: 55)], activeIndex: 0)
    _ = tabs.open(note("B"), inNewTab: false)
    #expect(tabs.active == tab("B"))
}

@Test func openNeverShowsANoteTwice() {
    var tabs = list(["A"])
    _ = tabs.open(note("B"), inNewTab: true)
    _ = tabs.open(note("A"), inNewTab: false)
    _ = tabs.open(note("B"), inNewTab: true)
    _ = tabs.open(note("C"), inNewTab: false)
    #expect(Set(names(tabs)).count == tabs.tabs.count)
}

// MARK: close

@Test func closeActiveSelectsRightNeighbour() {
    var tabs = list(["A", "B", "C"], active: 1)
    #expect(tabs.close(at: 1) == .closed(noteID: note("B")))
    #expect(names(tabs) == ["A", "C"])
    #expect(tabs.activeIndex == 1)
    #expect(tabs.active.noteID == note("C"))
}

@Test func closeLastPositionSelectsNewLast() {
    var tabs = list(["A", "B", "C"], active: 2)
    #expect(tabs.close(at: 2) == .closed(noteID: note("C")))
    #expect(names(tabs) == ["A", "B"])
    #expect(tabs.activeIndex == 1)
    #expect(tabs.active.noteID == note("B"))
}

@Test func closeFirstActiveTabSelectsTheNewFirst() {
    var tabs = list(["A", "B", "C"], active: 0)
    #expect(tabs.close(at: 0) == .closed(noteID: note("A")))
    #expect(tabs.activeIndex == 0)
    #expect(tabs.active.noteID == note("B"))
}

@Test func closeBeforeActiveKeepsActiveNote() {
    var tabs = list(["A", "B", "C"], active: 2)
    #expect(tabs.close(at: 0) == .closed(noteID: note("A")))
    #expect(names(tabs) == ["B", "C"])
    #expect(tabs.activeIndex == 1)
    #expect(tabs.active.noteID == note("C"))
}

@Test func closeAfterActiveKeepsActiveNote() {
    var tabs = list(["A", "B", "C"], active: 0)
    #expect(tabs.close(at: 2) == .closed(noteID: note("C")))
    #expect(names(tabs) == ["A", "B"])
    #expect(tabs.activeIndex == 0)
    #expect(tabs.active.noteID == note("A"))
}

@Test func closeOnlyTabReportsLastTab() {
    var tabs = TabList(tabs: [tab("A", selection: 3)], activeIndex: 0)
    let before = tabs
    #expect(tabs.close(at: 0) == .lastTab(noteID: note("A")))
    #expect(tabs == before)
}

@Test func closeNeverEmptiesTheList() {
    var tabs = list(["A", "B", "C"], active: 1)
    for index in [0, 0, 0] { _ = tabs.close(at: index) }
    #expect(names(tabs) == ["C"])
    #expect(tabs.activeIndex == 0)
}

// MARK: select

@Test func nextAndPreviousWrap() {
    var tabs = list(["A", "B", "C"], active: 2)
    tabs.selectNext()
    #expect(tabs.activeIndex == 0)
    tabs.selectPrevious()
    #expect(tabs.activeIndex == 2)
    tabs.selectPrevious()
    #expect(tabs.activeIndex == 1)
    tabs.selectNext()
    #expect(tabs.activeIndex == 2)
}

@Test func nextAndPreviousStayPutWithOneTab() {
    var tabs = list(["A"])
    tabs.selectNext()
    #expect(tabs.activeIndex == 0)
    tabs.selectPrevious()
    #expect(tabs.activeIndex == 0)
}

@Test func selectOutOfRangeIsIgnored() {
    var tabs = list(["A", "B", "C"], active: 1)
    tabs.select(-1)
    #expect(tabs.activeIndex == 1)
    tabs.select(3)
    #expect(tabs.activeIndex == 1)
    tabs.select(2)
    #expect(tabs.activeIndex == 2)
}

@Test func numberSelectsThatTab() {
    var tabs = list(["A", "B", "C", "D"], active: 3)
    tabs.select(number: 1)
    #expect(tabs.activeIndex == 0)
    tabs.select(number: 3)
    #expect(tabs.activeIndex == 2)
}

@Test func numberNineSelectsLast() {
    var tabs = list(["A", "B", "C"], active: 0)
    tabs.select(number: 9)
    #expect(tabs.activeIndex == 2)
}

@Test func numberNineSelectsLastWithMoreThanNineTabs() {
    var tabs = list((1...12).map { "N\($0)" }, active: 0)
    tabs.select(number: 9)
    #expect(tabs.activeIndex == 11)
    tabs.select(number: 8)
    #expect(tabs.activeIndex == 7)
}

@Test func numberBeyondCountIsIgnored() {
    var tabs = list(["A", "B", "C"], active: 1)
    tabs.select(number: 5)
    #expect(tabs.activeIndex == 1)
    tabs.select(number: 8)
    #expect(tabs.activeIndex == 1)
}

@Test func numberOutsideOneToNineIsIgnored() {
    var tabs = list(["A", "B", "C"], active: 1)
    tabs.select(number: 0)
    #expect(tabs.activeIndex == 1)
    tabs.select(number: -1)
    #expect(tabs.activeIndex == 1)
    tabs.select(number: 10)
    #expect(tabs.activeIndex == 1)
}

// MARK: view state, init and lookup

@Test func replaceNoteResetsViewState() {
    var tabs = TabList(
        tabs: [tab("A"), tab("B", selection: 12, scrollY: 300, scrollAnchor: 80), tab("C", selection: 4)],
        activeIndex: 2)
    tabs.replaceNote(at: 1, with: note("D"))
    #expect(tabs.tabs[1] == tab("D"))
    #expect(tabs.tabs[1].selection == 0)
    #expect(tabs.tabs[1].scrollY == 0)
    #expect(tabs.tabs[1].scrollAnchor == nil)
    #expect(tabs.tabs[2] == tab("C", selection: 4))
    #expect(tabs.activeIndex == 2)
}

@Test func updateViewStateChangesOnlyThatTab() {
    var tabs = list(["A", "B"], active: 1)
    tabs.updateViewState(at: 0, selection: 15, scrollAnchor: 200)
    #expect(tabs.tabs[0].selection == 15)
    #expect(tabs.tabs[0].scrollAnchor == 200)
    #expect(tabs.tabs[0].noteID == note("A"))
    #expect(tabs.tabs[1] == tab("B"))
    #expect(tabs.activeIndex == 1)
}

@Test func initClampsActiveIndex() {
    #expect(list(["A", "B", "C"], active: 7).activeIndex == 2)
    #expect(list(["A", "B", "C"], active: -4).activeIndex == 0)
    #expect(list(["A", "B", "C"], active: 1).activeIndex == 1)
}

@Test func activeIsTheSelectedTab() {
    let tabs = list(["A", "B", "C"], active: 1)
    #expect(tabs.active == tab("B"))
}

@Test func indexOfFindsAnOpenNote() {
    let tabs = list(["A", "B", "C"])
    #expect(tabs.index(of: note("C")) == 2)
    #expect(tabs.index(of: note("A")) == 0)
    #expect(tabs.index(of: note("Z")) == nil)
}

@Test func sessionCarriesTabsActiveIndexAndFontSize() {
    let tabs = TabList(tabs: [tab("A", selection: 2, scrollAnchor: 10), tab("B")], activeIndex: 1)
    #expect(
        tabs.session(fontSize: 17)
            == SessionState(tabs: tabs.tabs, activeTabIndex: 1, fontSize: 17))
}
