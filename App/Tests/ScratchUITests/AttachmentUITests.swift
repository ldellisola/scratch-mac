import AppKit
import XCTest

/// Covers docs/features/attachments.md ("Pasting and dropping", "Selecting and deleting a token") with real key events and
/// the real pasteboard: ⌘V of a file reference makes an attachment that survives a quit and a relaunch, and Backspace twice
/// deletes it and ⌘Z, after an autosave, brings it back with its file (spec §6.4, §6.5, plan 5 task 5, Review Focus 1). The
/// hosted tests cannot press keys, and an undo group ends with a turn of the run loop, which a hosted test never has.
///
/// The test runner puts the file's URL on `NSPasteboard.general`, which the app reads when it pastes, so each test sets what
/// it pastes first.
@MainActor
final class AttachmentUITests: XCTestCase {
    private static let tokenPattern =
        #"\[\[attachment:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\]\]"#

    private func launchEditor(file: StaticString = #filePath, line: UInt = #line) -> (XCUIApplication, XCUIElement) {
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(
            editor.waitForExistence(timeout: 10), "the editor text view did not appear", file: file, line: line)
        return (app, editor)
    }

    /// A PNG of 64 x 40 pixels called `name` in a folder of its own. A sandboxed test runner's own temporary directory is in
    /// its container, which the app may not read, so that case uses /tmp (as `UITestSupport.makeDataDirectory` does).
    private func makePNG(named name: String) throws -> URL {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let base = sandboxed ? URL(fileURLWithPath: "/tmp", isDirectory: true) : FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("ScratchUIAttachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemOrange.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 64, height: 40))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func putOnPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func text(of editor: XCUIElement) -> String {
        editor.value as? String ?? ""
    }

    /// The tokens in `text`, in order.
    private func tokens(in text: String) -> [String] {
        var found: [String] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: Self.tokenPattern, options: .regularExpression, range: searchRange) {
            found.append(String(text[range]))
            searchRange = range.upperBound..<text.endIndex
        }
        return found
    }

    /// The id inside a token `[[attachment:<id>]]`.
    private func id(of token: String) -> String {
        String(token.dropFirst("[[attachment:".count).dropLast(2))
    }

    /// What `debug.state` says about the attachments of the note: for each token of its text the id and whether the copy is
    /// in place (`isCopied`).
    private func attachmentStates(in app: XCUIApplication) -> [(id: String, copied: Bool)] {
        guard let list = UITestSupport.debugState(in: app)["attachments"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String, let copied = entry["copied"] as? Bool else { return nil }
            return (id, copied)
        }
    }

    private func waitForCopy(of id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line)
    {
        let done = UITestSupport.wait { self.attachmentStates(in: app).contains { $0.id == id && $0.copied } }
        XCTAssertTrue(
            done, "the copy of \(id) is in place: \(UITestSupport.debugState(in: app))", file: file, line: line)
    }

    private func dataDirectory(of app: XCUIApplication) -> URL? {
        let arguments = app.launchArguments
        guard let flag = arguments.firstIndex(of: "-ScratchDataDir"), flag + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }

    // MARK: Pasting

    /// ⌘V of a file reference is an attachment: one token in the note, its copy in place, and both are there after ⌘Q and a
    /// relaunch.
    func testPastedImageShowsAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()
        let picture = try makePNG(named: "pasted-picture.png")
        putOnPasteboard(picture)

        app.typeKey("v", modifierFlags: .command)

        let pasted = UITestSupport.wait { self.tokens(in: self.text(of: editor)).count == 1 }
        XCTAssertTrue(pasted, "⌘V of a file makes one token: \(text(of: editor).debugDescription)")
        let token = try XCTUnwrap(tokens(in: text(of: editor)).first)
        XCTAssertEqual(text(of: editor), token + "\n", "the token is a line of its own")
        waitForCopy(of: id(of: token), in: app)

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let restored = UITestSupport.editor(in: relaunched)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "the editor text view did not appear after relaunch")
        XCTAssertEqual(tokens(in: text(of: restored)), [token], "the token is still in the note")
        waitForCopy(of: id(of: token), in: relaunched)
        if let directory = dataDirectory(of: app) {
            let stored = directory.appendingPathComponent("attachments/\(id(of: token))/pasted-picture.png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path), "the copy is at \(stored.path)")
        }
    }

    // MARK: Deleting and undoing

    /// Review Focus 1: Backspace once selects the attachment, a second press deletes it, and ⌘Z after the autosave brings
    /// the token back with its file intact.
    func testUndoAfterDeletingAnAttachmentBringsItBack() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()
        let picture = try makePNG(named: "undo-picture.png")
        putOnPasteboard(picture)

        app.typeKey("v", modifierFlags: .command)

        let pasted = UITestSupport.wait { self.tokens(in: self.text(of: editor)).count == 1 }
        XCTAssertTrue(pasted, "⌘V of a file makes one token: \(text(of: editor).debugDescription)")
        let original = text(of: editor)
        let token = try XCTUnwrap(tokens(in: original).first)
        waitForCopy(of: id(of: token), in: app)

        app.typeKey(.delete, modifierFlags: [])
        app.typeKey(.delete, modifierFlags: [])
        let isDeleted = UITestSupport.wait { self.text(of: editor).isEmpty }
        XCTAssertTrue(isDeleted, "two Backspaces delete the attachment: \(text(of: editor).debugDescription)")

        // The deletion is saved before ⌘Z, and nothing may remove the file for it.
        Thread.sleep(forTimeInterval: 1.5)
        app.typeKey("z", modifierFlags: .command)

        UITestSupport.expectText(original, in: editor, "⌘Z brings the token back")
        waitForCopy(of: id(of: token), in: app)
        if let directory = dataDirectory(of: app) {
            let stored = directory.appendingPathComponent("attachments/\(id(of: token))/undo-picture.png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path), "the file is still at \(stored.path)")
        }
    }
}
