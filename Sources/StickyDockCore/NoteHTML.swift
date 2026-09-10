import Foundation

/// Converts between the plain text StickyDock edits and the HTML Apple Notes stores.
///
/// Two facts from the spike drive this whole type:
///
/// 1. The Notes `body` property is HTML. A literal newline inside it collapses to
///    a space, so every line has to be wrapped in its own `<div>` and a blank line
///    has to be `<div><br></div>`.
/// 2. There is no `fromHTML` here on purpose. The Notes `body` *getter* drops the
///    trailing semicolon off entities, so `&amp;` reads back as `&amp`, which is
///    not decodable. Reading always goes through the read-only `plaintext`
///    property instead, which is already correct text. See `NotesBridge`.
public enum NoteHTML {

    /// Wraps plain text as the HTML that Apple Notes expects in a note body.
    public static func toHTML(_ text: String) -> String {
        let lines = normalisedLines(text)
        guard !lines.isEmpty else { return "<div><br></div>" }
        return lines.map { line in
            line.isEmpty ? "<div><br></div>" : "<div>\(escape(line))</div>"
        }.joined()
    }

    /// The note's display title: the first line that has something on it.
    public static func title(of text: String) -> String {
        let first = normalisedLines(text)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        guard let first, !first.isEmpty else { return "Untitled" }
        return first.count > 60 ? String(first.prefix(60)) : first
    }

    // MARK: - Private

    private static func normalisedLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        // Notes on iOS and pasted content can both bring CRLF in.
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// The ampersand has to go first. Escaping `<` first would produce `&lt;`,
    /// and the ampersand pass would then mangle it into `&amp;lt;`.
    private static func escape(_ line: String) -> String {
        line.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
