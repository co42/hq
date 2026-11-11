import HQKit
import Testing

@Test func anUntouchedEditorWritesNothing() {
    #expect(TextMerge.commit(base: "Old status.", mine: "Old status.", theirs: "New status from a session.") == .unchanged)
    #expect(TextMerge.commit(base: "Text\n", mine: "Text", theirs: "Other") == .unchanged)
}

@Test func anEditOverAnUnchangedNoteIsWritten() {
    #expect(TextMerge.commit(base: "a\nb", mine: "a\nb\nc", theirs: "a\nb") == .write("a\nb\nc"))
    #expect(TextMerge.commit(base: "a", mine: "b", theirs: "b") == .write("b"))
}

@Test func changesOnDifferentLinesJoin() {
    let base = "Goal.\n\n## Done when\n- [ ] one\n- [ ] two\n\n## Status\nStarted."
    let mine = "Goal.\n\n## Done when\n- [x] one\n- [ ] two\n\n## Status\nStarted."
    let theirs = "Goal.\n\n## Done when\n- [ ] one\n- [ ] two\n\n## Status\nMerged in #418."
    #expect(TextMerge.commit(base: base, mine: mine, theirs: theirs)
        == .write("Goal.\n\n## Done when\n- [x] one\n- [ ] two\n\n## Status\nMerged in #418."))
}

@Test func insertionsAtTheEndAndTheStartJoin() {
    #expect(TextMerge.merge(base: "a\nb\nc", mine: "top\na\nb\nc", theirs: "a\nb\nc\nbottom") == "top\na\nb\nc\nbottom")
}

@Test func theSameLinesChangedTwiceKeepTheUsersText() {
    #expect(TextMerge.commit(base: "a\nb\nc", mine: "a\nmine\nc", theirs: "a\ntheirs\nc") == .conflict("a\nmine\nc"))
    #expect(TextMerge.commit(base: "a\nb", mine: "a\nb\nmine", theirs: "a\nb\ntheirs") == .conflict("a\nb\nmine"))
}

@Test func theSameChangeOnBothSidesIsOne() {
    #expect(TextMerge.commit(base: "a\nb", mine: "a\nc", theirs: "a\nc") == .write("a\nc"))
    #expect(TextMerge.merge(base: "a\nb\nc", mine: "a\nB\nc\nd", theirs: "a\nB\nc") == "a\nB\nc\nd")
}

@Test func deletionsJoinWithEditsElsewhere() {
    #expect(TextMerge.merge(base: "a\nb\nc\nd", mine: "a\nc\nd", theirs: "a\nb\nc\nD") == "a\nc\nD")
}
