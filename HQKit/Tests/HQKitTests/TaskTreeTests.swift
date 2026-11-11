import Foundation
import Testing
@testable import HQKit

/// Tasks: 1 (children 2, 3; 3 has 4), 5. Backlog: 6, 7.
private func sample() -> TaskTree {
    TaskTree([
        .init(id: 1, list: .overview, order: 1),
        .init(id: 2, parent: 1, order: 1),
        .init(id: 3, parent: 1, order: 2),
        .init(id: 4, parent: 3, order: 1),
        .init(id: 5, list: .overview, order: 2),
        .init(id: 6, list: .backlog, order: 1),
        .init(id: 7, list: .backlog, order: 2),
    ])
}

/// The tree after applying changes, as the app does.
private func applying(_ changes: [Int: TaskTree.Placement]?, to tree: TaskTree) -> TaskTree {
    var nodes = tree.nodes
    for (id, placement) in changes ?? [:] {
        nodes[id] = .init(id: id, parent: placement.parent, list: placement.list, order: placement.order)
    }
    return TaskTree(Array(nodes.values))
}

@Test func treeReadsParentsListsAndOrder() {
    let tree = sample()
    #expect(tree.top(.overview) == [1, 5])
    #expect(tree.top(.backlog) == [6, 7])
    #expect(tree.children(of: 1) == [2, 3])
    #expect(tree.outline(.overview) == [1, 2, 3, 4, 5])
    #expect(tree.list(of: 4) == .overview)
    #expect(tree.ancestors(of: 4) == [3, 1])
    #expect(tree.subtree(of: 1) == [1, 2, 3, 4])
}

@Test func missingParentsAndCyclesSitAtTheTop() {
    let tree = TaskTree([
        .init(id: 1, parent: 99, list: .overview, order: 1),
        .init(id: 2, parent: 3, list: .backlog, order: 1),
        .init(id: 3, parent: 2, list: .backlog, order: 2),
        .init(id: 4, parent: 2, order: 1),
    ])
    #expect(tree.top(.overview) == [1])
    #expect(tree.top(.backlog) == [2, 3])
    #expect(tree.parent(of: 4) == 2)
}

@Test func newTasksGoAfterOrAsFirstChild() throws {
    let tree = sample()
    let after = try #require(tree.placeNew(after: 2, asFirstChild: false))
    #expect(after.0.parent == 1 && after.0.order > 1 && after.0.order < 2 && after.changes.isEmpty)
    let child = try #require(tree.placeNew(after: 3, asFirstChild: true))
    #expect(child.0.parent == 3 && child.0.order < 1)
    let end = try #require(tree.placeNew(in: .list(.overview)))
    #expect(end.0.parent == nil && end.0.list == .overview && end.0.order > 2)
    let top = try #require(tree.placeNew(in: .list(.backlog), at: 0))
    #expect(top.0.list == .backlog && top.0.order < 1)
}

@Test func indentAndOutdent() {
    let tree = sample()
    let indented = applying(tree.indent(3), to: tree)
    #expect(indented.children(of: 2) == [3] && indented.subtree(of: 3) == [3, 4])
    #expect(tree.indent(2) == nil)
    #expect(tree.indent(1) == nil)
    let out = applying(tree.outdent(3), to: tree)
    #expect(out.top(.overview) == [1, 3, 5] && out.children(of: 1) == [2] && out.children(of: 3) == [4])
    #expect(tree.outdent(1) == nil)
    let deep = applying(tree.outdent(4), to: tree)
    #expect(deep.children(of: 1) == [2, 3, 4])
}

@Test func shiftAmongSiblings() {
    let tree = sample()
    #expect(applying(tree.shift(5, by: -1), to: tree).top(.overview) == [5, 1])
    #expect(applying(tree.shift(2, by: 1), to: tree).children(of: 1) == [3, 2])
    #expect(tree.shift(1, by: -1) == nil)
    #expect(tree.shift(5, by: 1) == nil)
    // Past the first or last sibling: out one level, before or after the parent.
    let up = applying(tree.shift(2, by: -1), to: tree)
    #expect(up.top(.overview) == [2, 1, 5] && up.children(of: 1) == [3])
    let down = applying(tree.shift(3, by: 1), to: tree)
    #expect(down.top(.overview) == [1, 3, 5] && down.children(of: 1) == [2] && down.subtree(of: 3) == [3, 4])
    #expect(applying(tree.shift(4, by: -1), to: tree).children(of: 1) == [2, 4, 3])
}

@Test func moveBetweenLists() throws {
    let tree = sample()
    let backlog = applying(tree.moveToList(3, .backlog), to: tree)
    #expect(backlog.top(.backlog) == [3, 6, 7])
    #expect(backlog.subtree(of: 3) == [3, 4] && backlog.list(of: 4) == .backlog)
    #expect(backlog.children(of: 1) == [2])
    let tasks = applying(tree.moveToList(7, .overview), to: tree)
    #expect(tasks.top(.overview) == [1, 5, 7])
    #expect(tree.moveToList(1, .overview) == nil)
}

@Test func dropsLandWhereTheOutlineShows() {
    let tree = sample()
    // On a row: its last child.
    #expect(applying(tree.move([6], to: .task(5), at: 0), to: tree).children(of: 5) == [6])
    // Between rows: the index counts the dragged row where it is now.
    #expect(applying(tree.move([1], to: .list(.overview), at: 2), to: tree).top(.overview) == [5, 1])
    #expect(applying(tree.move([5], to: .list(.overview), at: 0), to: tree).top(.overview) == [5, 1])
    // On a list's header: the end of that list.
    #expect(applying(tree.move([2], to: .list(.backlog), at: tree.top(.backlog).count), to: tree).top(.backlog) == [6, 7, 2])
    // Several rows keep their order; a child dragged with its parent rides along.
    let both = applying(tree.move([7, 6, 4, 3], to: .list(.overview), at: 1), to: tree)
    #expect(both.top(.overview) == [1, 7, 6, 3, 5] && both.children(of: 3) == [4])
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
    #expect(tree.move([99], to: .list(.overview), at: 0) == nil)
}

@Test func siblingsRenumberWhenTheGapIsTooSmall() throws {
    let tree = TaskTree([
        .init(id: 1, list: .overview, order: 1),
        .init(id: 2, list: .overview, order: 1 + 1e-7),
        .init(id: 3, list: .overview, order: 5),
    ])
    let changes = try #require(tree.move([3], to: .list(.overview), at: 1))
    #expect(changes.count == 3)
    #expect(applying(changes, to: tree).top(.overview) == [1, 3, 2])
    #expect(changes.values.map(\.order).sorted() == [1, 2, 3])
}
