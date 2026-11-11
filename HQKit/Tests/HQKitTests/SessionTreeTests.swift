import Foundation
import Testing
@testable import HQKit

/// a (b (c), d), e; f closed under e; g closed, h open under it.
private func sample(open: Set<String> = ["a", "b", "c", "d", "e", "h"]) -> SessionTree {
    let nodes: [SessionTree.Node] = [
        .init(id: "a", order: 1), .init(id: "b", parent: "a", order: 2), .init(id: "c", parent: "b", order: 1),
        .init(id: "d", parent: "a", order: 1), .init(id: "e", order: 2), .init(id: "f", parent: "e", order: 1),
        .init(id: "g", order: 3), .init(id: "h", parent: "g", order: 1),
    ]
    return SessionTree(nodes.map { var node = $0; node.open = open.contains(node.id); return node })
}

@Test func sessionTreeShowsTopLevelSessionsInOrder() {
    let tree = sample()
    #expect(tree.roots == ["a", "e", "g"])
    #expect(tree.children(of: "a") == ["d", "b"])
    #expect(tree.rows(under: "a") == [.init(id: "d", depth: 1), .init(id: "b", depth: 1), .init(id: "c", depth: 2)])
    #expect(tree.root(of: "c") == "a")
    #expect(tree.ancestors(of: "c") == ["b", "a"])
    #expect(tree.descendants(of: "a") == ["d", "b", "c"])
}

@Test func sessionTreeKeepsAClosedParentWhileOneOfItsTeamRuns() {
    let tree = sample()
    // g closed, h open: g stays on the grid. f closed under e: it leaves e's rows.
    #expect(tree.isShown("g"))
    #expect(tree.rows(under: "e").isEmpty)
    #expect(!tree.isShown("f"))
    // h closes too: g leaves with it.
    #expect(!sample(open: ["a", "b", "c", "d", "e"]).roots.contains("g"))
    // A closed middle session stays while the one under it runs.
    let middle = sample(open: ["a", "c", "e"])
    #expect(middle.rows(under: "a") == [.init(id: "b", depth: 1), .init(id: "c", depth: 2)])
}

@Test func sessionTreeReadsAMissingParentOrALoopAsTopLevel() {
    let tree = SessionTree([
        .init(id: "x", parent: "gone", order: 1),
        .init(id: "y", parent: "z", order: 2), .init(id: "z", parent: "y", order: 3),
        .init(id: "w", parent: "y", order: 4),
    ])
    #expect(tree.roots == ["x", "y", "z", "w"])
    #expect(tree.parent(of: "x") == nil)
}

@Test func sessionTreeNeverMovesASessionUnderItsOwnTeam() {
    let tree = sample()
    #expect(!tree.canMove("a", under: "c"))
    #expect(!tree.canMove("a", under: "a"))
    #expect(tree.canMove("c", under: "e"))
    #expect(tree.canMove("e", under: "c"))
    #expect(!tree.canMove("e", under: "missing"))
}
