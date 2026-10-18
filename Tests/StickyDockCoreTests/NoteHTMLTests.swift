import Testing
@testable import StickyDockCore

@Suite("NoteHTML")
struct NoteHTMLTests {
    // Apple Notes stores a note body as HTML. A literal newline collapses to a
    // space, which the spike proved the hard way, so every line has to be a div.

    @Test func plainLinesBecomeDivs() {
        #expect(NoteHTML.toHTML("one\ntwo") == "<div>one</div><div>two</div>")
    }

    @Test func blankLineBecomesBrDiv() {
        #expect(NoteHTML.toHTML("a\n\nb") == "<div>a</div><div><br></div><div>b</div>")
    }

    @Test func entitiesAreEscaped() {
        #expect(NoteHTML.toHTML("a & b < c > d") == "<div>a &amp; b &lt; c &gt; d</div>")
    }

    @Test func ampersandIsEscapedBeforeAngleBrackets() {
        // Escaping < first would turn "&lt;" into "&amp;lt;" on the next pass.
        #expect(NoteHTML.toHTML("&<") == "<div>&amp;&lt;</div>")
    }

    @Test func emptyTextIsOneEmptyDiv() {
        #expect(NoteHTML.toHTML("") == "<div><br></div>")
    }

    @Test func trailingNewlineKeepsItsEmptyLine() {
        #expect(NoteHTML.toHTML("a\n") == "<div>a</div><div><br></div>")
    }

    @Test func unicodeSurvives() {
        #expect(NoteHTML.toHTML("héllo 🎉") == "<div>héllo 🎉</div>")
    }

    @Test func carriageReturnsAreNormalised() {
        #expect(NoteHTML.toHTML("a\r\nb") == "<div>a</div><div>b</div>")
    }

    @Test func titleIsFirstNonEmptyLineTrimmed() {
        #expect(NoteHTML.title(of: "\n  Shopping list  \nmilk") == "Shopping list")
    }

    @Test func titleOfEmptyTextIsUntitled() {
        #expect(NoteHTML.title(of: "   \n  ") == "Untitled")
    }

    @Test func titleIsTruncatedAtSixtyCharacters() {
        #expect(NoteHTML.title(of: String(repeating: "x", count: 100)).count == 60)
    }

    @Test func titleCountsCharactersNotBytes() {
        #expect(NoteHTML.title(of: String(repeating: "🎉", count: 100)).count == 60)
    }
}

/// Apple Notes reads a body as HTML, which collapses whitespace: a tab became a
/// space, a leading tab vanished, two spaces became one. Probed against the live
/// app: `white-space:pre-wrap` on the line's div keeps all of them exactly.
@Suite("NoteHTML whitespace")
struct NoteHTMLWhitespaceTests {
    private let keep = "<div style=\"white-space:pre-wrap\">"

    @Test func aLineWithATabIsProtected() {
        #expect(NoteHTML.toHTML("title\na\tb") == "<div>title</div>\(keep)a\tb</div>")
    }

    @Test func doubleSpacesAndLeadingSpacesAreProtected() {
        #expect(NoteHTML.toHTML("a  b").hasPrefix(keep))
        #expect(NoteHTML.toHTML(" indented").hasPrefix(keep))
        #expect(NoteHTML.toHTML("\tindented").hasPrefix(keep))
    }

    @Test func ordinaryLinesAreLeftExactlyAsTheyWere() {
        // Not every note gets restyled: only lines that need it.
        #expect(NoteHTML.toHTML("title\nplain line") == "<div>title</div><div>plain line</div>")
        #expect(NoteHTML.toHTML("one trailing space ") == "<div>one trailing space </div>")
    }

    @Test func formattedTextIsProtectedToo() {
        let rich = RichText(text: "title\nbold\there",
                            runs: [TextStyleRun(location: 6, length: 4, bold: true)])
        let html = NoteHTML.toHTML(rich)
        #expect(html.contains("\(keep)<b>bold</b>\there</div>"))
        #expect(html.hasPrefix("<div>title</div>"))
    }

    @Test func formattingIsStillRecoveredFromAProtectedLine() {
        let rich = RichText(text: "t\nbold\there",
                            runs: [TextStyleRun(location: 2, length: 4, bold: true)])
        let runs = NoteHTML.styleRuns(fromBody: NoteHTML.toHTML(rich), plainText: rich.text)
        #expect(runs == [TextStyleRun(location: 2, length: 4, bold: true)])
    }
}
