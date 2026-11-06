import Foundation

/// Tasks as one tree per list: top-level tasks in Tasks or the Backlog, subtasks under them.
/// Built from each note's `parent`, `list` and `order`; every operation returns the placements
/// that change, so the app writes only those notes.
public struct TaskTree: Sendable {
    public struct Node: Sendable, Hashable {
        public var id: Int
        public var parent: Int?
        public var list: TaskList
        public var order: Double

        public init(id: Int, parent: Int? = nil, list: TaskList = .backlog, order: Double = 0) {
            self.id = id
            self.parent = parent
            self.list = list
            self.order = order
        }
    }

    /// Where a task sits: at the top of a list, or under a task.
    public enum Container: Sendable, Hashable {
        case list(TaskList)
        case task(Int)
    }

    /// A task's place as its note stores it. A subtask keeps its root's list.
    public struct Placement: Sendable, Hashable {
        public var parent: Int?
        public var list: TaskList
        public var order: Double

        public init(parent: Int?, list: TaskList, order: Double) {
            self.parent = parent
            self.list = list
            self.order = order
        }
    }

    /// The gap under which siblings are numbered again.
    public static let minimumGap = 1e-6

    public private(set) var nodes: [Int: Node]
    private var containers: [Int: Container] = [:]
    private var children: [Container: [Int]] = [:]

    public init(_ nodes: [Node]) {
        self.nodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cyclic = Self.cyclic(self.nodes)
        for node in self.nodes.values {
            let container: Container
            if let parent = node.parent, self.nodes[parent] != nil, !cyclic.contains(node.id) {
                container = .task(parent)
            } else {
                container = .list(node.list)
            }
            containers[node.id] = container
            children[container, default: []].append(node.id)
        }
        for key in children.keys {
            children[key]?.sort { (self.nodes[$0]!.order, $0) < (self.nodes[$1]!.order, $1) }
        }
    }

    /// Nodes that are part of a parent cycle: they sit at the top of their list.
    private static func cyclic(_ nodes: [Int: Node]) -> Set<Int> {
        var result = Set<Int>()
        for start in nodes.keys {
            var path: [Int] = []
            var seen = Set<Int>()
            var current: Int? = start
            while let id = current, nodes[id] != nil {
                if seen.contains(id) {
                    if let index = path.firstIndex(of: id) { result.formUnion(path[index...]) }
                    break
                }
                seen.insert(id)
                path.append(id)
                current = nodes[id]?.parent
            }
        }
        return result
    }

    // MARK: Reading

    public func children(of container: Container) -> [Int] { children[container] ?? [] }

    public func children(of id: Int) -> [Int] { children(of: .task(id)) }

    public func top(_ list: TaskList) -> [Int] { children(of: .list(list)) }

    public func container(of id: Int) -> Container? { containers[id] }

    public func parent(of id: Int) -> Int? {
        if case .task(let parent) = containers[id] { return parent }
        return nil
    }

    public func index(of id: Int) -> Int? {
        containers[id].flatMap { children(of: $0).firstIndex(of: id) }
    }

    /// The list a task shows in: its own, or its root's.
    public func list(of id: Int) -> TaskList? {
        var current = id
        while true {
            switch containers[current] {
            case .list(let list): return list
            case .task(let parent): current = parent
            case nil: return nil
            }
        }
    }

    public func root(of id: Int) -> Int {
        var current = id
        while case .task(let parent) = containers[current] { current = parent }
        return current
    }

    /// Ancestors, nearest first.
    public func ancestors(of id: Int) -> [Int] {
        var result: [Int] = []
        var current = id
        while case .task(let parent) = containers[current] {
            result.append(parent)
            current = parent
        }
        return result
    }

    public func depth(of id: Int) -> Int { ancestors(of: id).count }

    /// The task and everything under it, in outline order.
    public func subtree(of id: Int) -> [Int] {
        [id] + children(of: id).flatMap { subtree(of: $0) }
    }

    public func contains(_ id: Int) -> Bool { nodes[id] != nil }

    /// Every task of a list in outline order, children after their parent.
    public func outline(_ list: TaskList) -> [Int] {
        top(list).flatMap { subtree(of: $0) }
    }

    public func placement(of id: Int) -> Placement? {
        guard let node = nodes[id], let list = list(of: id) else { return nil }
        return Placement(parent: parent(of: id), list: list, order: node.order)
    }

    // MARK: Operations

    /// Where a new task goes for Return on `id`: its first child when asked, else right after it.
    public func placeNew(after id: Int, asFirstChild: Bool) -> (Placement, changes: [Int: Placement])? {
        guard let container = containers[id], let index = index(of: id) else { return nil }
        return asFirstChild ? placeNew(in: .task(id), at: 0) : placeNew(in: container, at: index + 1)
    }

    /// A new task at an index of a container (`nil`: the end).
    public func placeNew(in container: Container, at index: Int? = nil) -> (Placement, changes: [Int: Placement])? {
        if case .task(let parent) = container, nodes[parent] == nil { return nil }
        let siblings = children(of: container)
        let at = min(max(index ?? siblings.count, 0), siblings.count)
        let fresh = Int.min
        let result = insert([fresh], into: container, at: at, siblings: siblings)
        guard let placement = result[fresh] else { return nil }
        var changes = result
        changes[fresh] = nil
        return (placement, changes)
    }

    /// Tab: the task becomes the last child of its previous sibling.
    public func indent(_ id: Int) -> [Int: Placement]? {
        guard let container = containers[id], let index = index(of: id), index > 0 else { return nil }
        let previous = children(of: container)[index - 1]
        return move([id], to: .task(previous), at: children(of: previous).count)
    }

    /// ⇧Tab: the task moves out one level, right after its parent.
    public func outdent(_ id: Int) -> [Int: Placement]? {
        guard case .task(let parent) = containers[id], let outer = containers[parent], let index = index(of: parent) else { return nil }
        return move([id], to: outer, at: index + 1)
    }

    /// ⇧↑ ⇧↓: one place among its siblings; past the first or the last, out one level, before or after its parent.
    public func shift(_ id: Int, by offset: Int) -> [Int: Placement]? {
        guard let container = containers[id], let index = index(of: id) else { return nil }
        let siblings = children(of: container)
        let target = index + offset
        guard siblings.indices.contains(target) else {
            guard case .task(let parent) = container, let outer = containers[parent], let at = self.index(of: parent) else { return nil }
            return move([id], to: outer, at: offset < 0 ? at : at + 1)
        }
        // Indexes count the moving task, as a drop's do.
        return move([id], to: container, at: offset > 0 ? target + 1 : target)
    }

    /// Move to the Backlog (its top) or to Tasks (its end), as a top-level task.
    public func moveToList(_ id: Int, _ list: TaskList) -> [Int: Placement]? {
        guard contains(id) else { return nil }
        if case .list(list) = containers[id] { return nil }
        return move([id], to: .list(list), at: list == .backlog ? 0 : top(list).count)
    }

    /// True when the tasks can land in `container`: never into one of their own subtrees.
    public func canMove(_ ids: [Int], to container: Container) -> Bool {
        guard !ids.isEmpty, ids.allSatisfy(contains) else { return false }
        guard case .task(let target) = container else { return true }
        guard contains(target) else { return false }
        let path = Set([target] + ancestors(of: target))
        return ids.allSatisfy { !path.contains($0) }
    }

    /// Moves tasks to `index` among the children of `container`, as the outline shows them:
    /// the index counts the moved tasks where they are now. Nil when refused.
    public func move(_ ids: [Int], to container: Container, at index: Int) -> [Int: Placement]? {
        // A task and its ancestor dragged together: the ancestor carries it.
        let moving = ids.filter { id in !ancestors(of: id).contains(where: ids.contains) }
        guard canMove(moving, to: container) else { return nil }
        let current = children(of: container)
        let clamped = min(max(index, 0), current.count)
        let before = current[..<clamped].filter { moving.contains($0) }.count
        let siblings = current.filter { !moving.contains($0) }
        var sequence = siblings
        sequence.insert(contentsOf: moving, at: clamped - before)
        // Dropped where they already are: nothing changes.
        if sequence == current { return [:] }
        return insert(moving, into: container, at: clamped - before, siblings: siblings)
    }

    /// Places `ids` in order at `index` of `siblings` (which hold none of them), between the
    /// neighbors' orders, numbering the siblings again when the gap is too small.
    private func insert(_ ids: [Int], into container: Container, at index: Int, siblings: [Int]) -> [Int: Placement] {
        let parent: Int?
        let list: TaskList
        switch container {
        case .list(let l):
            parent = nil
            list = l
        case .task(let p):
            parent = p
            list = self.list(of: p) ?? .backlog
        }
        let order = { (id: Int) in self.nodes[id]?.order ?? 0 }
        let low = index > 0 ? order(siblings[index - 1]) : nil
        let high = index < siblings.count ? order(siblings[index]) : nil
        var changes: [Int: Placement] = [:]
        let count = Double(ids.count)
        let orders: [Double]
        switch (low, high) {
        case (nil, nil): orders = ids.indices.map { Double($0 + 1) }
        case (let low?, nil): orders = ids.indices.map { low + Double($0 + 1) }
        case (nil, let high?): orders = ids.indices.map { high - count + Double($0) }
        case (let low?, let high?):
            let step = (high - low) / (count + 1)
            if step < Self.minimumGap {
                var sequence = siblings
                sequence.insert(contentsOf: ids, at: index)
                for (position, id) in sequence.enumerated() {
                    changes[id] = Placement(parent: parent, list: list, order: Double(position + 1))
                }
                return changes
            }
            orders = ids.indices.map { low + step * Double($0 + 1) }
        }
        for (id, value) in zip(ids, orders) {
            changes[id] = Placement(parent: parent, list: list, order: value)
        }
        return changes
    }
}
