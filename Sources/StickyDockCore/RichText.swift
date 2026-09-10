import Foundation

/// A stretch of text carrying one combination of bold, italic and underline.
///
/// Offsets are UTF-16, matching `NSAttributedString`, so the bridge to the
/// editor is a straight copy with no index translation to get wrong.
public struct TextStyleRun: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(
        location: Int, length: Int,
        bold: Bool = false, italic: Bool = false, underline: Bool = false
    ) {
        self.location = location
        self.length = length
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }

    public var isPlain: Bool { !bold && !italic && !underline }
}

/// Text plus the formatting applied to parts of it.
///
/// Kept free of AppKit so every conversion is testable. Only non-plain runs are
/// stored, so a note with no formatting carries an empty array rather than one
/// run covering everything.
public struct RichText: Equatable, Sendable {
    public var text: String
    public var runs: [TextStyleRun]

    public init(text: String, runs: [TextStyleRun] = []) {
        self.text = text
        self.runs = runs.filter { !$0.isPlain && $0.length > 0 }.sorted { $0.location < $1.location }
    }

    public var isPlain: Bool { runs.isEmpty }
}
