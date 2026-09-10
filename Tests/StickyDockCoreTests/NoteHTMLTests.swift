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
