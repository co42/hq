import Testing
@testable import HQKit

/// The outline's start of a long description (T-368 item 7): whole blocks up to the limit, the crossing one left out.
struct MarkdownPreviewTests {
    @Test func shortTextStaysWhole() {
        let text = "One.\n\nTwo."
        #expect(Markdown.preview(text, lines: 20) == (text, 0))
    }

    @Test func cutsBetweenBlocks() {
        let text = "Intro.\n\n- a\n- b\n\n| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nEnd."
        let (shown, hidden) = Markdown.preview(text, lines: 6)
        #expect(shown == "Intro.\n\n- a\n- b")
        #expect(hidden == 7)
    }

    @Test func aLongFirstTableKeepsItsFirstRows() {
        let rows = (1...30).map { "| \($0) | x |" }.joined(separator: "\n")
        let (shown, hidden) = Markdown.preview("| N | X |\n|---|---|\n" + rows, lines: 5)
        #expect(shown == "| N | X |\n|---|---|\n| 1 | x |\n| 2 | x |\n| 3 | x |")
        #expect(hidden == 27)
    }

    @Test func aLongFirstCodeBlockKeepsItsFirstLinesClosed() {
        let code = "```swift\n" + (1...30).map { "let a\($0) = \($0)" }.joined(separator: "\n") + "\n```"
        let (shown, hidden) = Markdown.preview(code, lines: 4)
        #expect(shown == "```swift\nlet a1 = 1\nlet a2 = 2\n```")
        #expect(hidden == 29)
    }

    @Test func aLongFirstListKeepsWholeItems() {
        let list = (1...10).map { "- item \($0)\n  more about \($0)" }.joined(separator: "\n")
        let (shown, _) = Markdown.preview(list, lines: 5)
        #expect(shown == "- item 1\n  more about 1\n- item 2\n  more about 2")
    }

    @Test func aDiagramStaysWhole() {
        let diagram = "```mermaid\ngraph LR\n" + (1...30).map { "  a\($0) --> b\($0)" }.joined(separator: "\n") + "\n```\n\nAfter."
        let (shown, hidden) = Markdown.preview(diagram, lines: 10)
        #expect(shown.hasPrefix("```mermaid") && shown.hasSuffix("  a30 --> b30\n```"))
        #expect(hidden == 2)
    }

    @Test func checkboxesKeepTheirNumbers() {
        let text = (1...30).map { "- [ ] step \($0)" }.joined(separator: "\n")
        let (shown, _) = Markdown.preview(text, lines: 10)
        #expect(Markdown.taskLines(shown) == Array(Markdown.taskLines(text).prefix(Markdown.taskLines(shown).count)))
    }
}
