import Testing
@testable import HQKit

/// Goal 1: 2 (done), 3 (doing), 4 (blocked by 3), 5 (after 4), 6 (Blocked), 7 (blocked by 2, done: holds nothing).
/// 8 has 9 (blocked by 6) and 10.
private func story() -> TaskFlow {
    TaskFlow([
        .init(id: 1, doing: true),
        .init(id: 2, parent: 1, done: true),
        .init(id: 3, parent: 1, doing: true),
        .init(id: 4, parent: 1, blockedBy: [3]),
        .init(id: 5, parent: 1, after: [4]),
        .init(id: 6, parent: 1, blocked: true),
        .init(id: 7, parent: 1, blockedBy: [2]),
        .init(id: 8, parent: 1),
        .init(id: 9, parent: 8, blockedBy: [6]),
        .init(id: 10, parent: 8),
    ])
}

@Test func flowStatesFollowTheLinks() {
    let flow = story()
    #expect(flow.state(2) == .done)
    #expect(flow.state(3) == .doing)
    #expect(flow.state(4) == .blockedBy)
    #expect(flow.state(5) == .waiting)
    #expect(flow.state(6) == .blocked)
    #expect(flow.state(7) == .ready)
    #expect(flow.state(9) == .blockedBy)
    #expect(flow.openBlockers(4) == [3])
    #expect(flow.openBlockers(7).isEmpty)
    #expect(flow.openBefore(5) == [4])
}

@Test func flowBlockedWinsOverDoing() {
    let flow = TaskFlow([.init(id: 1, doing: true, blocked: true), .init(id: 2, doing: true, blockedBy: [3]), .init(id: 3)])
    #expect(flow.state(1) == .blocked)
    #expect(flow.state(2) == .blockedBy)
}

@Test func flowLinkToAMissingTaskHoldsNothing() {
    let flow = TaskFlow([.init(id: 1, blockedBy: [99], after: [98])])
    #expect(flow.state(1) == .ready)
}

@Test func flowTallyCountsLeaves() {
    let tally = story().tally(of: 1)
    #expect(tally.done == 1)
    #expect(tally.doing == 1)
    #expect(tally.blocked == 3)
    #expect(tally.waiting == 1)
    #expect(tally.ready == 2)
    #expect(tally.total == 8)
    #expect(story().leaves(of: 1) == [2, 3, 4, 5, 6, 7, 9, 10])
}

@Test func flowLeavesEndWhenParentsGoInACircle() {
    // Notes edited by hand: 1 under 2, 2 under 1, 3 under 1.
    let flow = TaskFlow([.init(id: 1, parent: 2), .init(id: 2, parent: 1), .init(id: 3, parent: 1)])
    #expect(Set(flow.leaves(of: 1)) == [2, 3])
    #expect(flow.tally(of: 2).total == 1)
}

@Test func flowWhatMattersIsBlockingAndDoing() {
    let flow = story()
    let tree = TaskTree((1...10).map { TaskTree.Node(id: $0, parent: [9, 10].contains($0) ? 8 : $0 == 1 ? nil : 1, order: Double($0)) })
    // 3 doing and blocking 4; 6 Blocked but blocking 9; 2 done; 4, 7 and 9 blocked: they don't count.
    #expect(flow.isBlocking(3) && flow.isBlocking(6) && !flow.isBlocking(2) && !flow.isBlocking(4))
    #expect(flow.important(under: 1, in: tree, doing: 5) == [3, 6])
    #expect(flow.important(under: 1, in: tree, doing: 0) == [3, 6])
    #expect(flow.important(under: 8, in: tree, doing: 5).isEmpty)
    let deep = TaskFlow([.init(id: 1), .init(id: 2, parent: 1), .init(id: 3, parent: 2, doing: true), .init(id: 4, parent: 1, blockedBy: [5]), .init(id: 5)])
    let deepTree = TaskTree((1...5).map { TaskTree.Node(id: $0, parent: $0 == 3 ? 2 : $0 == 1 ? nil : 1, order: Double($0)) })
    // 5 blocks 4 and shows; 2 shows on the way to 3.
    #expect(deep.important(under: 1, in: deepTree, doing: 5) == [2, 3, 5])
    let many = TaskFlow([.init(id: 1)] + (2...9).map { .init(id: $0, parent: 1, doing: true) })
    let wide = TaskTree([.init(id: 1)] + (2...9).map { .init(id: $0, parent: 1, order: Double($0)) })
    #expect(many.important(under: 1, in: wide, doing: 5) == [2, 3, 4, 5, 6])
}

@Test func flowRefusesCirclesAndWhatTheTreeSays() {
    let flow = story()
    #expect(flow.refusal(4, .blockedBy, 4) == .itself)
    #expect(flow.refusal(2, .after, 3) == .done)
    #expect(flow.refusal(4, .blockedBy, 3) == .already)
    #expect(flow.refusal(8, .blockedBy, 9) == .partOf)
    #expect(flow.refusal(3, .blockedBy, 4) == .circle)
    #expect(flow.refusal(4, .after, 5) == .circle)
    #expect(flow.refusal(9, .after, 1) == .circle)
    #expect(flow.refusal(10, .after, 9) == nil)
    #expect(flow.dependents(of: 3, .blockedBy) == [4])
    #expect(flow.dependents(of: 4, .after) == [5])
}
