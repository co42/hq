import Testing
@testable import HQKit

/// Notes as Obsidian, the user and HQ write them.
private let corpus = [
    "---\ntitle: Dedup layers\nstatus: todo\ntags: [registry, perf]\n---\n\n# Dedup layers\n\nText.\n",
    "---\ntitle: \"Dedup: on push\" # renamed\naliases:\n  - one\n\n  - two\ncreated: 2026-11-03\n---\nBody\n",
    "---\nsummary: |\n  First line\n\n  Third line\nstatus: doing\n---\n\n\nTwo blank lines above.\n",
    "---\ntags: [\"a #b\", c] # a comment\n---\n",
]

@Test(arguments: corpus)
func frontMatterComesBackAsItWas(_ text: String) {
    #expect(FrontMatter(text).text == text)
}

@Test func frontMatterKeepsANewlineOnItsKeysLine() {
    var note = FrontMatter("---\ntitle: T\n---\nBody\n")
    note.set("blocked_reason", "Waiting on X\nsee Slack\tnow \\ \"quoted\"")
    #expect(note.lines.count == 2)
    #expect(note.lines.last == #"blocked_reason: "Waiting on X\nsee Slack\tnow \\ \"quoted\"""#)
    let again = FrontMatter(note.text)
    #expect(again.string("blocked_reason") == "Waiting on X\nsee Slack\tnow \\ \"quoted\"")
    #expect(again.string("title") == "T" && again.body == "Body\n")
}

@Test func frontMatterReadsWhatItUsedToMisread() {
    // A quoted value with a comment after it, a quoted list item with one.
    let commented = FrontMatter("---\ntitle: \"Dedup: on push\" # renamed\nwho: 'it''s me'\naliases:\n  - \"a: b\" # note\n---\n")
    #expect(commented.string("title") == "Dedup: on push")
    #expect(commented.string("who") == "it's me")
    #expect(commented.list("aliases") == ["a: b"])
    // ` #` inside a quoted item of an inline list.
    #expect(FrontMatter("---\ntags: [\"a #b\", c] # a comment\n---\n").list("tags") == ["a #b", "c"])
    // Blocks of text.
    let blocks = FrontMatter("---\nkeep: |\n  one\n  two\nstrip: |-\n  one\n\n  three\nfold: >-\n  one\n  two\n\n  three\nnext: x\n---\n")
    #expect(blocks.string("keep") == "one\ntwo\n")
    #expect(blocks.string("strip") == "one\n\nthree")
    #expect(blocks.string("fold") == "one two\nthree")
    #expect(blocks.string("next") == "x")
    // A fence with a byte order mark or a trailing space.
    #expect(FrontMatter("\u{FEFF}---\ntitle: T\n--- \nBody").string("title") == "T")
    #expect(FrontMatter("--- \ntitle: T\n---\nBody").body == "Body")
}

@Test func frontMatterReplacesABlockOfTextWhole() {
    var note = FrontMatter("---\nreason: |\n  one\n\n  two\nstatus: todo\n---\n")
    note.set("reason", "new")
    #expect(note.lines == ["reason: new", "status: todo"])
}
