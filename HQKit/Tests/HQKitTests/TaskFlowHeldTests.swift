import Testing
@testable import HQKit

/// 1 is Blocked: 2 (todo), 3 (doing), 4 (done), 5 has 6 (after 7). 8 is blocked by 9 (open): 10 under it.
/// 11 is blocked by 12 (done): 13 under it is ready.
private func held() -> TaskFlow {
    TaskFlow([
        .init(id: 1, blocked: true),
        .init(id: 2, parent: 1),
        .init(id: 3, parent: 1, doing: true),
        .init(id: 4, parent: 1, done: true),
        .init(id: 5, parent: 1),
        .init(id: 6, parent: 5, after: [7]),
        .init(id: 7),
        .init(id: 8, blockedBy: [9]),
        .init(id: 9),
        .init(id: 10, parent: 8),
        .init(id: 11, blockedBy: [12]),
        .init(id: 12, done: true),
        .init(id: 13, parent: 11),
    ])
}

@Test func flowABlockedTaskHoldsWhatsUnderIt() {
    let flow = held()
    #expect(flow.state(2) == .held)
    #expect(flow.state(6) == .held)
    #expect(flow.state(10) == .held)
    #expect(flow.holder(6) == 1 && flow.holder(10) == 8)
    // Doing stays doing, done stays done; a done blocker holds nothing.
    #expect(flow.state(3) == .doing && flow.state(4) == .done)
    #expect(flow.state(13) == .ready && flow.holder(13) == nil)
    #expect(flow.state(2).isBlocked)
}

@Test func flowHeldLeavesAreNotReadyInTheTally() {
    let tally = held().tally(of: 1)
    #expect(tally.ready == 0)
    #expect(tally.blocked == 2 && tally.doing == 1 && tally.done == 1 && tally.total == 4)
}

@Test func flowHoldersEndWhenParentsGoInACircle() {
    let flow = TaskFlow([.init(id: 1, parent: 2), .init(id: 2, parent: 1), .init(id: 3, parent: 1)])
    #expect(flow.holder(3) == nil && flow.state(3) == .ready)
}
