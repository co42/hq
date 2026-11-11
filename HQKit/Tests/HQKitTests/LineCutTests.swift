import Testing
@testable import HQKit

struct LineCutTests {
    let long = "Julien in #registry-incidents: Heads-up on the eu-west upload retries: the canary went red again overnight after the S3 client bump, every multipart complete above 5 GB retried three times"

    @Test func shortTextStaysWhole() {
        #expect(LineCut.line("Retry budget canary") == "Retry budget canary")
        #expect(LineCut.wrap("Retry budget canary") == "Retry budget canary")
    }

    @Test func oneLineCutsAtAWord() {
        let line = LineCut.line(long)
        #expect(line.count <= LineCut.width)
        #expect(line.hasSuffix("…"))
        #expect(long.hasPrefix(String(line.dropLast())))
        #expect(!line.dropLast().hasSuffix(" "))
    }

    @Test func anAddressCutsInTheMiddle() {
        let address = "status.example.com/incidents/2026-11-10-eu-west-uploads/timeline/details/with/a/very/long/path"
        let line = LineCut.line(address, middle: true)
        #expect(line.count == LineCut.width)
        #expect(line.hasPrefix("status.example.com") && line.hasSuffix("long/path") && line.contains("…"))
    }

    @Test func newlinesBecomeOneLine() {
        #expect(LineCut.line("first\nsecond") == "first second")
    }

    @Test func wrapKeepsEveryWordWithinTheWidth() {
        let wrapped = LineCut.wrap(long, width: 40, lines: 20)
        let lines = wrapped.split(separator: "\n")
        #expect(lines.allSatisfy { $0.count <= 40 })
        #expect(lines.joined(separator: " ") == long)
    }

    @Test func wrapCutsAfterItsLastLine() {
        let wrapped = LineCut.wrap(long, width: 40, lines: 2)
        let lines = wrapped.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.count <= 40 })
        #expect(lines[1].hasSuffix("…"))
    }

    @Test func wrapKeepsParagraphsAndBreaksLongWords() {
        let wrapped = LineCut.wrap("Slack: hi\nClick to open", width: 40)
        #expect(wrapped == "Slack: hi\nClick to open")
        let word = String(repeating: "a", count: 90)
        #expect(LineCut.wrap(word, width: 40, lines: 10).split(separator: "\n").map(\.count) == [40, 40, 10])
    }
}
