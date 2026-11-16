import Foundation
import Testing
@testable import HQKit

/// Top level: 1 (children 2, 3; 3 has 4), 5, 6, 7.
private func sample() -> TaskTree {
    TaskTree([
        .init(id: 1, order: 1),
        .init(id: 2, parent: 1, order: 1),
        .init(id: 3, parent: 1, order: 2),
        .init(id: 4, parent: 3, order: 1),
        .init(id: 5, order: 2),
        .init(id: 6, order: 3),
        .init(id: 7, order: 4),
    ])
}

/// The tree after applying changes, as the app does.
private func applying(_ changes: [Int: TaskTree.Placement]?, to tree: TaskTree) -> TaskTree {
    var nodes = tree.nodes
    for (id, placement) in changes ?? [:] {
        nodes[id] = .init(id: id, parent: placement.parent, order: placement.order)
    }
    return TaskTree(Array(nodes.values))
}

@Test func treeReadsParentsAndOrder() {
    let tree = sample()
    #expect(tree.top() == [1, 5, 6, 7])
    #expect(tree.children(of: 1) == [2, 3])
    #expect(tree.outline() == [1, 2, 3, 4, 5, 6, 7])
    #expect(tree.ancestors(of: 4) == [3, 1])
    #expect(tree.subtree(of: 1) == [1, 2, 3, 4])
}

@Test func missingParentsAndCyclesSitAtTheTop() {
    let tree = TaskTree([
        .init(id: 1, parent: 99, order: 1),
        .init(id: 2, parent: 3, order: 2),
        .init(id: 3, parent: 2, order: 3),
        .init(id: 4, parent: 2, order: 1),
    ])
    #expect(tree.top() == [1, 2, 3])
    #expect(tree.parent(of: 4) == 2)
}

@Test func newTasksGoAfterOrAsFirstChild() throws {
    let tree = sample()
    let after = try #require(tree.placeNew(after: 2, asFirstChild: false))
    #expect(after.0.parent == 1 && after.0.order > 1 && after.0.order < 2 && after.changes.isEmpty)
    let child = try #require(tree.placeNew(after: 3, asFirstChild: true))
    #expect(child.0.parent == 3 && child.0.order < 1)
    let end = try #require(tree.placeNew(in: .top))
    #expect(end.0.parent == nil && end.0.order > 4)
    let first = try #require(tree.placeNew(in: .top, at: 0))
    #expect(first.0.parent == nil && first.0.order < 1)
}

@Test func indentAndOutdent() {
    let tree = sample()
    let indented = applying(tree.indent(3), to: tree)
    #expect(indented.children(of: 2) == [3] && indented.subtree(of: 3) == [3, 4])
    #expect(tree.indent(2) == nil)
    #expect(tree.indent(1) == nil)
    let out = applying(tree.outdent(3), to: tree)
    #expect(out.top() == [1, 3, 5, 6, 7] && out.children(of: 1) == [2] && out.children(of: 3) == [4])
    #expect(tree.outdent(1) == nil)
    let deep = applying(tree.outdent(4), to: tree)
    #expect(deep.children(of: 1) == [2, 3, 4])
}

@Test func shiftAmongSiblings() {
    let tree = sample()
    #expect(applying(tree.shift(5, by: -1), to: tree).top() == [5, 1, 6, 7])
    #expect(applying(tree.shift(2, by: 1), to: tree).children(of: 1) == [3, 2])
    #expect(tree.shift(1, by: -1) == nil)
    #expect(tree.shift(7, by: 1) == nil)
    // Past the first or last sibling: out one level, before or after the parent.
    let up = applying(tree.shift(2, by: -1), to: tree)
    #expect(up.top() == [2, 1, 5, 6, 7] && up.children(of: 1) == [3])
    let down = applying(tree.shift(3, by: 1), to: tree)
    #expect(down.top() == [1, 3, 5, 6, 7] && down.children(of: 1) == [2] && down.subtree(of: 3) == [3, 4])
    #expect(applying(tree.shift(4, by: -1), to: tree).children(of: 1) == [2, 4, 3])
}

@Test func shiftAndIndentSkipHiddenSiblings() {
    // 1's subtasks 2, 8 (hidden, as Hide Done hides a done one), 3.
    let tree = TaskTree(sample().nodes.values.map { $0 } + [.init(id: 8, parent: 1, order: 1.5)])
    let shown = { (id: Int) in id != 8 }
    #expect(applying(tree.shift(3, by: -1, shown: shown), to: tree).children(of: 1) == [3, 2, 8])
    #expect(applying(tree.shift(2, by: 1, shown: shown), to: tree).children(of: 1) == [8, 3, 2])
    #expect(applying(tree.indent(3, shown: shown), to: tree).children(of: 2) == [3])
    // Its only shown sibling is past it: out one level.
    #expect(applying(tree.shift(2, by: -1, shown: shown), to: tree).top() == [2, 1, 5, 6, 7])
}

@Test func dropsLandWhereTheOutlineShows() {
    let tree = sample()
    // On a row: its last child.
    #expect(applying(tree.move([6], to: .task(5), at: 0), to: tree).children(of: 5) == [6])
    // Between rows: the index counts the dragged row where it is now.
    #expect(applying(tree.move([1], to: .top, at: 2), to: tree).top() == [5, 1, 6, 7])
    #expect(applying(tree.move([5], to: .top, at: 0), to: tree).top() == [5, 1, 6, 7])
    // On the list's header: its end.
    #expect(applying(tree.move([2], to: .top, at: tree.top().count), to: tree).top() == [1, 5, 6, 7, 2])
    // Several rows keep their order; a child dragged with its parent rides along.
    let both = applying(tree.move([7, 6, 4, 3], to: .top, at: 1), to: tree)
    #expect(both.top() == [1, 7, 6, 3, 5] && both.children(of: 3) == [4])
    // Dropped where it already is: nothing to write.
    #expect(tree.move([2], to: .task(1), at: 0) == [:])
    #expect(tree.move([2], to: .task(1), at: 1) == [:])
}

@Test func dropsNeverLandInTheirOwnSubtree() {
    let tree = sample()
    #expect(tree.move([1], to: .task(4), at: 0) == nil)
    #expect(tree.move([1], to: .task(1), at: 0) == nil)
    #expect(!tree.canMove([3], to: .task(4)))
    #expect(tree.canMove([4], to: .task(2)))
    #expect(tree.move([99], to: .top, at: 0) == nil)
}

@Test func siblingsRenumberWhenTheGapIsTooSmall() throws {
    let tree = TaskTree([
        .init(id: 1, order: 1),
        .init(id: 2, order: 1 + 1e-7),
        .init(id: 3, order: 5),
    ])
    let changes = try #require(tree.move([3], to: .top, at: 1))
    #expect(changes.count == 3)
    #expect(applying(changes, to: tree).top() == [1, 3, 2])
    #expect(changes.values.map(\.order).sorted() == [1, 2, 3])
}
