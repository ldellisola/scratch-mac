import AppKit
import ScratchCore

/// What VoiceOver reads for a range of the styled note (plan 6 task 8, docs/features/accessibility.md, "VoiceOver"): the note
/// as the editor shows it, and not the characters that stand behind what it shows.
///
/// The note's text holds markers (`**`, backticks, `- `, `[ ]`, fence lines, `[[attachment:<id>]]`), which the styler hides
/// or draws as something else. They are read from the attributes that the styler gave them and replaced by what they are:
///
/// | In the note | Spoken |
/// |---|---|
/// | hidden and revealed markers | nothing |
/// | a bullet marker | "bullet" |
/// | `[ ]` | "unchecked" |
/// | `[x]` | "checked" |
/// | an image token | "image, <name>" |
/// | a file token | "file, <name>" |
/// | a token whose file is being copied | "attachment, <name>, copying" |
/// | a missing token | "missing attachment" |
/// | an opening fence | "code block, <label>", or "code block" with no label |
/// | a closing fence | "end of code block" |
///
/// Every other character is read as it is. Nothing here changes the storage, and `accessibilityValue` stays the stored text,
/// so that the ranges and the caret that VoiceOver works with agree with the text (`NoteTextView`).
enum SpokenText {
    /// The words for `range` of a styled note. The range is cut to the text. A marker is replaced by its words when the range
    /// holds its first character, and says nothing when the range starts inside it: the words were not asked for.
    static func spoken(_ storage: NSAttributedString, range: NSRange) -> String {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 else { return "" }
        let text = storage.string as NSString
        var result = ""
        var location = clamped.location
        while location < NSMaxRange(clamped) {
            // One paragraph at a time: a token line, a fence line and a list marker are all in one paragraph, and the marks
            // that matter are on its first character.
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            let piece = NSIntersectionRange(paragraph, clamped)
            result += spokenPiece(of: paragraph, within: piece, in: storage, text: text)
            location = NSMaxRange(paragraph)
        }
        return result
    }

    // MARK: A paragraph

    /// The words for `piece`, the part of `paragraph` that was asked for.
    private static func spokenPiece(
        of paragraph: NSRange, within piece: NSRange, in storage: NSAttributedString, text: NSString
    ) -> String {
        if let mark = storage.attribute(.scratchAttachment, at: paragraph.location, effectiveRange: nil)
            as? AttachmentMark
        {
            let token = NSRange(
                location: paragraph.location, length: min(AttachmentToken.lineLength, paragraph.length))
            return replacing(token, with: words(for: mark), within: piece, in: text)
        }
        if let mark = storage.attribute(.scratchCodeBlock, at: paragraph.location, effectiveRange: nil)
            as? CodeBlockMark,
            mark.part != .body
        {
            let phrase = mark.part == .opening ? words(forOpeningFenceOf: mark) : "end of code block"
            return replacing(contentRange(of: paragraph, in: text), with: phrase, within: piece, in: text)
        }
        return spokenMarkers(of: paragraph, within: piece, in: storage, text: text)
    }

    /// The text of `piece` with `span` (inside the paragraph that holds it) replaced by `phrase`: the phrase when the piece
    /// holds the first character of the span, and nothing for the part of the span that it holds otherwise.
    private static func replacing(_ span: NSRange, with phrase: String, within piece: NSRange, in text: NSString)
        -> String
    {
        let before = NSRange(
            location: piece.location, length: max(min(span.location, NSMaxRange(piece)) - piece.location, 0))
        let afterStart = max(NSMaxRange(span), piece.location)
        let after = NSRange(location: afterStart, length: max(NSMaxRange(piece) - afterStart, 0))
        let holdsStart = piece.location <= span.location && span.location < NSMaxRange(piece)
        return substring(of: before, in: text) + (holdsStart ? phrase : "") + substring(of: after, in: text)
    }

    /// The characters of `paragraph` without its line break.
    private static func contentRange(of paragraph: NSRange, in text: NSString) -> NSRange {
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getParagraphStart(
            &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: paragraph.location, length: 0))
        return NSRange(location: paragraph.location, length: contentsEnd - paragraph.location)
    }

    private static func substring(of range: NSRange, in text: NSString) -> String {
        range.length > 0 ? text.substring(with: range) : ""
    }

    // MARK: Markers

    /// The words for a paragraph with no token and no fence: its characters, and for each marker run of the piece what the
    /// marker is called. The marker's role is on each of its characters, so a run is read once.
    private static func spokenMarkers(
        of paragraph: NSRange, within piece: NSRange, in storage: NSAttributedString, text: NSString
    ) -> String {
        var result = ""
        var index = piece.location
        while index < NSMaxRange(piece) {
            var run = NSRange(location: 0, length: 0)
            let value = storage.attribute(.scratchMarker, at: index, longestEffectiveRange: &run, in: paragraph)
            let end = min(NSMaxRange(run), NSMaxRange(piece))
            if let raw = value as? String, let role = MarkerRole(rawValue: raw) {
                // A run that began before the piece was started by an earlier call, which said what it is.
                if run.location >= piece.location { result += words(for: role) }
            } else {
                result += substring(of: NSRange(location: index, length: end - index), in: text)
            }
            index = max(end, index + 1)
        }
        return result
    }

    private static func words(for role: MarkerRole) -> String {
        switch role {
        case .bullet: "bullet"
        case .checkboxOpen: "unchecked"
        case .checkboxChecked: "checked"
        case .hidden, .revealed, .fence, .attachment: ""
        }
    }

    // MARK: Tokens and fences

    private static func words(for mark: AttachmentMark) -> String {
        switch mark.kind {
        case .image: "image, \(mark.fileName)"
        case .file: "file, \(mark.fileName)"
        case .copying: "attachment, \(mark.fileName), copying"
        case .missing: "missing attachment"
        }
    }

    private static func words(forOpeningFenceOf mark: CodeBlockMark) -> String {
        mark.name.isEmpty ? "code block" : "code block, \(mark.name)"
    }
}
