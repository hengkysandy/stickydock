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

// MARK: - Formatting

extension NoteHTML {

    /// Wraps rich text as the HTML Apple Notes expects.
    ///
    /// Apple Notes keeps `<b>`, `<i>` and `<u>` verbatim, including nesting, so
    /// bold, italic and underline written here really do show up on the iPhone.
    /// Verified against the live app before this was built.
    public static func toHTML(_ rich: RichText) -> String {
        guard !rich.isPlain else { return toHTML(rich.text) }

        let units = Array(rich.text.utf16)
        guard !units.isEmpty else { return "<div><br></div>" }

        var styles = [Style](repeating: Style(), count: units.count)
        for run in rich.runs {
            let upper = min(run.location + run.length, units.count)
            guard run.location < upper else { continue }
            for index in max(0, run.location)..<upper {
                styles[index] = Style(bold: run.bold, italic: run.italic, underline: run.underline)
            }
        }

        var html = "<div>"
        var open = Style()
        var index = 0
        while index < units.count {
            // A newline ends the line. Every open tag is closed before the
            // </div>: a tag left open across a line break is invalid HTML and
            // Notes rewrites it into something else entirely.
            if units[index] == 0x000A {
                html += close(open)
                open = Style()
                html += "</div><div>"
                index += 1
                continue
            }
            let wanted = styles[index]
            if wanted != open {
                html += close(open)
                html += self.open(wanted)
                open = wanted
            }
            var scalarEnd = index + 1
            // Keep a surrogate pair together, or the escape below splits it.
            if units[index] >= 0xD800, units[index] <= 0xDBFF, scalarEnd < units.count {
                scalarEnd += 1
            }
            html += escape(String(decoding: units[index..<scalarEnd], as: UTF16.self))
            index = scalarEnd
        }
        html += close(open)
        html += "</div>"
        // A line that ended up with nothing in it still needs a <br> to survive.
        return html.replacingOccurrences(of: "<div></div>", with: "<div><br></div>")
    }

    /// Recovers formatting ranges from a note body, aligned to its plain text.
    ///
    /// The body and the plain text come from two different Notes properties for
    /// a reason: the `body` getter corrupts entities (`&amp;` reads back as
    /// `&amp`), while `plaintext` is always correct. So the characters come from
    /// `plaintext` and only the tag positions come from `body`.
    ///
    /// If the two do not agree once tags are stripped, this returns nothing at
    /// all. Dropping the formatting is the safe answer; guessing at offsets
    /// would put bold on the wrong words.
    public static func styleRuns(fromBody body: String, plainText: String) -> [TextStyleRun] {
        let parsed = parseBody(body)
        guard parsed.text == plainText else { return [] }

        var runs: [TextStyleRun] = []
        var index = 0
        while index < parsed.styles.count {
            let style = parsed.styles[index]
            var end = index + 1
            while end < parsed.styles.count, parsed.styles[end] == style { end += 1 }
            if !style.isPlain {
                runs.append(TextStyleRun(
                    location: index, length: end - index,
                    bold: style.bold, italic: style.italic, underline: style.underline
                ))
            }
            index = end
        }
        return runs
    }

    // MARK: - Private

    struct Style: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var isPlain: Bool { !bold && !italic && !underline }
    }

    /// A fixed nesting order, so the same rich text always serialises to exactly
    /// the same string. Sync compares hashes, and an unstable order would make
    /// an unchanged note look changed.
    private static func open(_ style: Style) -> String {
        (style.bold ? "<b>" : "") + (style.italic ? "<i>" : "") + (style.underline ? "<u>" : "")
    }

    private static func close(_ style: Style) -> String {
        (style.underline ? "</u>" : "") + (style.italic ? "</i>" : "") + (style.bold ? "</b>" : "")
    }

    /// Entity spellings Notes may hand back, longest first so `&amp;` is matched
    /// before `&amp`.
    private static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&amp", "&"),
        ("&quot;", "\""), ("&quot", "\""),
        ("&apos;", "'"), ("&apos", "'"),
        ("&#39;", "'"), ("&#39", "'"),
        ("&nbsp;", " "), ("&nbsp", " "),
        ("&lt;", "<"), ("&lt", "<"),
        ("&gt;", ">"), ("&gt", ">"),
    ]

    /// Walks the body once, collecting the characters and the style in force at
    /// each of them.
    private static func parseBody(_ body: String) -> (text: String, styles: [Style]) {
        var lines: [(String, [Style])] = []
        var lineText = ""
        var lineStyles: [Style] = []
        var stack: [String] = []
        // Notes puts a literal newline between one `</div>` and the next
        // `<div>`. It is layout in the source, not a line in the note, so text
        // outside a div is ignored when it is only whitespace.
        var insideDiv = false

        func currentStyle() -> Style {
            Style(
                bold: stack.contains("b") || stack.contains("strong"),
                italic: stack.contains("i") || stack.contains("em"),
                underline: stack.contains("u")
            )
        }

        func append(_ text: String) {
            guard insideDiv || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            let style = currentStyle()
            for unit in text.utf16 {
                lineText.append(Character(UnicodeScalar(unit) ?? " "))
                lineStyles.append(style)
            }
        }

        func endLine() {
            // Notes appends a <br> just inside the closing </div> of any line
            // that carries formatting. It is an artefact, not a blank line.
            if lineText.hasSuffix("\u{FFFF}") {
                lineText.removeLast()
                lineStyles.removeLast()
            }
            lines.append((lineText, lineStyles))
            lineText = ""
            lineStyles = []
        }

        var rest = Substring(body)
        while let open = rest.firstIndex(of: "<") {
            append(decode(String(rest[rest.startIndex..<open])))
            guard let close = rest[open...].firstIndex(of: ">") else { break }
            let tag = String(rest[rest.index(after: open)..<close]).lowercased()
            rest = rest[rest.index(after: close)...]

            let name = tag
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0 == " " || $0 == "/" || $0 == ">" })
                .first.map(String.init) ?? ""

            if tag.hasPrefix("/") {
                let closing = String(tag.dropFirst()).trimmingCharacters(in: .whitespaces)
                if closing == "div" {
                    endLine()
                    insideDiv = false
                }
                if let last = stack.lastIndex(of: closing) { stack.remove(at: last) }
            } else if name == "br" {
                // Marked, not emitted. If it turns out to be the artefact just
                // before </div> it is removed there; otherwise it is a newline.
                lineText.append("\u{FFFF}")
                lineStyles.append(currentStyle())
            } else if name == "div" {
                // Opening a div while one is already open means the previous was
                // never closed.
                if insideDiv { endLine() }
                insideDiv = true
            } else if ["b", "strong", "i", "em", "u"].contains(name), !tag.hasSuffix("/") {
                stack.append(name)
            }
        }
        append(decode(String(rest)))
        if insideDiv || !lineText.isEmpty { endLine() }

        // Any <br> still standing was a real line break inside a div.
        var text = ""
        var styles: [Style] = []
        for (offset, line) in lines.enumerated() {
            if offset > 0 {
                text.append("\n")
                styles.append(Style())
            }
            for (character, style) in zip(line.0, line.1) {
                if character == "\u{FFFF}" {
                    text.append("\n")
                    styles.append(Style())
                } else {
                    text.append(character)
                    styles.append(style)
                }
            }
        }
        return (text, styles)
    }

    private static func decode(_ text: String) -> String {
        var out = text
        for (entity, replacement) in entities {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}
