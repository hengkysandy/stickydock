import Testing
@testable import StickyDockCore

@Suite("Rich text and HTML")
struct RichTextHTMLTests {

    // MARK: - Writing

    @Test func plainRichTextProducesThePlainHTML() {
        let rich = RichText(text: "one\ntwo")
        #expect(NoteHTML.toHTML(rich) == NoteHTML.toHTML("one\ntwo"))
    }

    @Test func aBoldRunIsWrappedInB() {
        let rich = RichText(text: "hello world",
                            runs: [TextStyleRun(location: 0, length: 5, bold: true)])
        #expect(NoteHTML.toHTML(rich) == "<div><b>hello</b> world</div>")
    }

    @Test func italicAndUnderlineGetTheirOwnTags() {
        let rich = RichText(text: "ab", runs: [
            TextStyleRun(location: 0, length: 1, italic: true),
            TextStyleRun(location: 1, length: 1, underline: true),
        ])
        #expect(NoteHTML.toHTML(rich) == "<div><i>a</i><u>b</u></div>")
    }

    @Test func combinedStylesNestInAStableOrder() {
        let rich = RichText(text: "x", runs: [
            TextStyleRun(location: 0, length: 1, bold: true, italic: true, underline: true),
        ])
        #expect(NoteHTML.toHTML(rich) == "<div><b><i><u>x</u></i></b></div>")
    }

    @Test func formattingIsClosedAndReopenedAcrossALineBreak() {
        // A tag left open across a </div> is invalid and Notes mangles it.
        let rich = RichText(text: "a\nb",
                            runs: [TextStyleRun(location: 0, length: 3, bold: true)])
        #expect(NoteHTML.toHTML(rich) == "<div><b>a</b></div><div><b>b</b></div>")
    }

    @Test func entitiesInsideAStyledRunAreStillEscaped() {
        let rich = RichText(text: "a & b",
                            runs: [TextStyleRun(location: 0, length: 5, bold: true)])
        #expect(NoteHTML.toHTML(rich) == "<div><b>a &amp; b</b></div>")
    }

    // MARK: - Reading back

    @Test func parsingRecoversBoldItalicUnderline() {
        let body = "<div><b>bold</b> plain <i>it</i> <u>un</u></div>"
        let plain = "bold plain it un"
        let runs = NoteHTML.styleRuns(fromBody: body, plainText: plain)
        #expect(runs == [
            TextStyleRun(location: 0, length: 4, bold: true),
            TextStyleRun(location: 11, length: 2, italic: true),
            TextStyleRun(location: 14, length: 2, underline: true),
        ])
    }

    @Test func parsingHandlesNestedTags() {
        let runs = NoteHTML.styleRuns(fromBody: "<div><b><i>x</i></b></div>", plainText: "x")
        #expect(runs == [TextStyleRun(location: 0, length: 1, bold: true, italic: true)])
    }

    @Test func parsingToleratesTheSemicolonlessEntitiesNotesReturns() {
        // The Notes `body` getter really does return "&amp" for "&amp;".
        let runs = NoteHTML.styleRuns(
            fromBody: "<div><b>a &amp b</b></div>", plainText: "a & b"
        )
        #expect(runs == [TextStyleRun(location: 0, length: 5, bold: true)])
    }

    @Test func parsingToleratesTheTrailingBrNotesAdds() {
        let runs = NoteHTML.styleRuns(
            fromBody: "<div><b>bold</b><br></div>", plainText: "bold"
        )
        #expect(runs == [TextStyleRun(location: 0, length: 4, bold: true)])
    }

    @Test func parsingHandlesBlankLines() {
        let runs = NoteHTML.styleRuns(
            fromBody: "<div>a</div>\n<div><br></div>\n<div><b>b</b></div>",
            plainText: "a\n\nb"
        )
        #expect(runs == [TextStyleRun(location: 3, length: 1, bold: true)])
    }

    @Test func formattingIsDroppedWhenTheTextDoesNotLineUp() {
        // The safe answer. Guessing at offsets would bold the wrong words.
        let runs = NoteHTML.styleRuns(
            fromBody: "<div><b>completely different</b></div>", plainText: "short"
        )
        #expect(runs.isEmpty)
    }

    @Test func unknownTagsAreIgnoredRatherThanBreakingTheParse() {
        let runs = NoteHTML.styleRuns(
            fromBody: "<div><span class=\"x\"><b>a</b></span></div>", plainText: "a"
        )
        #expect(runs == [TextStyleRun(location: 0, length: 1, bold: true)])
    }

    @Test func plainBodyGivesNoRuns() {
        #expect(NoteHTML.styleRuns(fromBody: "<div>hello</div>", plainText: "hello").isEmpty)
    }

    // MARK: - The property that keeps sync from looping

    @Test func writingThenReadingBackGivesTheSameRuns() {
        let cases: [RichText] = [
            RichText(text: "plain"),
            RichText(text: "bold here", runs: [TextStyleRun(location: 0, length: 4, bold: true)]),
            RichText(text: "a\nb", runs: [TextStyleRun(location: 2, length: 1, italic: true)]),
            RichText(text: "x & y", runs: [TextStyleRun(location: 4, length: 1, underline: true)]),
            RichText(text: "mix", runs: [
                TextStyleRun(location: 0, length: 1, bold: true),
                TextStyleRun(location: 2, length: 1, italic: true, underline: true),
            ]),
            RichText(text: "line one\n\nline three",
                     runs: [TextStyleRun(location: 10, length: 4, bold: true, underline: true)]),
        ]
        for rich in cases {
            let html = NoteHTML.toHTML(rich)
            let recovered = NoteHTML.styleRuns(fromBody: html, plainText: rich.text)
            #expect(recovered == rich.runs, "round trip failed for \(rich.text)")
        }
    }
}
