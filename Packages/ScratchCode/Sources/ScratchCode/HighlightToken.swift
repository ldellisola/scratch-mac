import Foundation

/// What a coloured range is. The app has one colour for each (Plan 4 "Colours"); everything else is the text colour.
public enum HighlightKind: String, CaseIterable, Sendable {
    case keyword, string, comment, number, type, function, attribute, preprocessor
}

/// A coloured range of a text: UTF-16 units, relative to the text that was highlighted.
public struct HighlightToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: HighlightKind

    public init(range: NSRange, kind: HighlightKind) {
        self.range = range
        self.kind = kind
    }
}
