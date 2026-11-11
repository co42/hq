import Foundation

/// Where each task stands in its story, worked out from the tree, Blocked and the two links between tasks;
/// never stored. A task needs its subtasks; "blocked by" holds it until that task is done; Blocked and "blocked by" hold
/// what's under the task too; "after" is the order the user means and holds nothing.
public struct TaskFlow: Sendable {
    public struct Node: Sendable, Hashable {
        public var id: Int
        public var parent: Int?
        public var done: Bool
        public var doing: Bool
        public var blocked: Bool
        public var blockedBy: [Int]
        public var after: [Int]

        public init(id: Int, parent: Int? = nil, done: Bool = false, doing: Bool = false, blocked: Bool = false,
                    blockedBy: [Int] = [], after: [Int] = []) {
            self.id = id
            self.parent = parent
            self.done = done
            self.doing = doing
            self.blocked = blocked
            self.blockedBy = blockedBy
            self.after = after
        }
    }

    public enum State: String, Sendable, Hashable {
        /// Done.
        case done
        /// Blocked by the user or a session, with or without a reason.
        case blocked
        /// Blocked by a task that isn't done.
        case blockedBy
        case doing
        /// Not doing, under a task that's Blocked or blocked by an open one: it waits with it.
        case held
        /// After a task that isn't done.
        case waiting
        /// Todo, and nothing holds it.
        case ready

        /// It can't go on: Blocked, blocked by an open task, or under one of those.
        public var isBlocked: Bool { self == .blocked || self == .blockedBy || self == .held }
    }

    /// A story's leaves by state: what its progress bar and counts show.
    public struct Tally: Sendable, Hashable {
        public var done = 0
        public var doing = 0
        public var blocked = 0
        public var ready = 0
        public var waiting = 0
        public var total: Int { done + doing + blocked + ready + waiting }

        public init() {}
    }

    /// Why a link can't be made.
    public enum Refusal: Sendable, Hashable {
        case itself, done, already, partOf, circle
    }

    public enum Link: Sendable, Hashable {
        case blockedBy, after
    }

    private let nodes: [Int: Node]
    private let children: [Int: [Int]]
    /// Open tasks that hold an open task: it is blocked by them.
    private let holding: Set<Int>

    public init(_ nodes: [Node]) {
        self.nodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [Int: [Int]] = [:]
        for node in nodes { if let parent = node.parent, parent != node.id { children[parent, default: []].append(node.id) } }
        self.children = children
        let byID = self.nodes
        self.holding = Set(nodes.filter { !$0.done }.flatMap(\.blockedBy).filter { byID[$0].map { !$0.done } ?? false })
    }

    /// Open, and an open task is blocked by it.
    public func isBlocking(_ id: Int) -> Bool { holding.contains(id) }

    /// A link to a task that's gone or done holds nothing.
    private func open(_ id: Int) -> Bool { nodes[id].map { !$0.done } ?? false }

    public func state(_ id: Int) -> State {
        guard let node = nodes[id] else { return .ready }
        if node.done { return .done }
        if node.blocked { return .blocked }
        if node.blockedBy.contains(where: open) { return .blockedBy }
        if node.doing { return .doing }
        if holder(id) != nil { return .held }
        if node.after.contains(where: open) { return .waiting }
        return .ready
    }

    /// The nearest open task above it that's Blocked or blocked by an open task: it holds what's under it.
    public func holder(_ id: Int) -> Int? {
        var seen: Set<Int> = [id]
        var next = nodes[id]?.parent
        while let parent = next, seen.insert(parent).inserted, let node = nodes[parent] {
            if !node.done, node.blocked || node.blockedBy.contains(where: open) { return parent }
            next = node.parent
        }
        return nil
    }

    /// The tasks still holding it, in its order.
    public func openBlockers(_ id: Int) -> [Int] { (nodes[id]?.blockedBy ?? []).filter(open) }

    /// The tasks it still comes after.
    public func openBefore(_ id: Int) -> [Int] { (nodes[id]?.after ?? []).filter(open) }

    /// Its subtasks without subtasks, at any depth; each once, also when notes' parents go in a circle.
    public func leaves(of id: Int) -> [Int] {
        var out: [Int] = []
        var seen: Set<Int> = [id]
        var stack = (children[id] ?? []).reversed().map { $0 }
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            let kids = (children[next] ?? []).filter { !seen.contains($0) }
            if kids.isEmpty { out.append(next) } else { stack.append(contentsOf: kids.reversed()) }
        }
        return out
    }

    public func tally(of id: Int) -> Tally {
        var tally = Tally()
        for leaf in leaves(of: id) {
            switch state(leaf) {
            case .done: tally.done += 1
            case .doing: tally.doing += 1
            case .blocked, .blockedBy, .held: tally.blocked += 1
            case .ready: tally.ready += 1
            case .waiting: tally.waiting += 1
            }
        }
        return tally
    }

    /// What a task that shows only blocked and doing subtasks shows under it: every one Blocked, blocked by an open task
    /// or doing, at any depth, with the tasks between them and it (2026-11-11).
    public func blockedOrDoing(under id: Int, in tree: TaskTree) -> Set<Int> {
        var shown = Set<Int>()
        func visit(_ id: Int) -> Bool {
            var any = false
            for kid in tree.children(of: id) where visit(kid) || [.blocked, .blockedBy, .doing].contains(state(kid)) {
                shown.insert(kid)
                any = true
            }
            return any
        }
        _ = visit(id)
        return shown
    }

    /// The tasks that are blocked by it, or come after it.
    public func dependents(of id: Int, _ link: Link) -> [Int] {
        nodes.values.filter { (link == .blockedBy ? $0.blockedBy : $0.after).contains(id) }.map(\.id).sorted()
    }

    /// Nil when `task` may be blocked by, or come after, `other`.
    public func refusal(_ task: Int, _ link: Link, _ other: Int) -> Refusal? {
        guard task != other else { return .itself }
        guard let node = nodes[task] else { return .itself }
        if node.done { return .done }
        if (link == .blockedBy ? node.blockedBy : node.after).contains(other) { return .already }
        if descendants(of: task).contains(other) { return .partOf }
        if needs(other).contains(task) { return .circle }
        return nil
    }

    private func descendants(of id: Int) -> Set<Int> {
        var out = Set<Int>()
        var stack = children[id] ?? []
        while let next = stack.popLast() {
            if out.insert(next).inserted { stack.append(contentsOf: children[next] ?? []) }
        }
        return out
    }

    /// Everything a task waits for: its subtasks, what blocks it and what it comes after, and theirs.
    private func needs(_ id: Int) -> Set<Int> {
        var out = Set<Int>()
        var stack = [id]
        while let next = stack.popLast() {
            guard let node = nodes[next] else { continue }
            for other in (children[next] ?? []) + node.blockedBy + node.after where out.insert(other).inserted { stack.append(other) }
        }
        return out
    }
}
