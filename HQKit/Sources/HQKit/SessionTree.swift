import Foundation

/// Sessions as teams: a session another one started sits under it. The grid shows the top-level ones; a team's
/// sessions show inside its card. A parent that isn't there, or a loop, reads as top level.
public struct SessionTree: Sendable {
    public struct Node: Sendable, Hashable {
        public var id: String
        public var parent: String?
        public var order: Double
        public var started: Date
        /// Open: its Claude runs, or it ended and is still on the grid. A closed one shows only while one under it is open.
        public var open: Bool

        public init(id: String, parent: String? = nil, order: Double = 0, started: Date = .distantPast, open: Bool = true) {
            self.id = id
            self.parent = parent
            self.order = order
            self.started = started
            self.open = open
        }
    }

    /// A session under a team's top card: depth 1 is a direct child.
    public struct Row: Sendable, Hashable {
        public var id: String
        public var depth: Int

        public init(id: String, depth: Int) {
            self.id = id
            self.depth = depth
        }
    }

    public private(set) var nodes: [String: Node]
    private var parents: [String: String] = [:]
    private var children: [String: [String]] = [:]
    private var top: [String] = []
    /// Shown: open, or closed with an open session under it.
    private var shown: Set<String> = []

    public init(_ nodes: [Node]) {
        self.nodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for node in self.nodes.values {
            if let parent = node.parent, self.nodes[parent] != nil, !Self.loops(from: node.id, in: self.nodes) {
                parents[node.id] = parent
                children[parent, default: []].append(node.id)
            } else {
                top.append(node.id)
            }
        }
        let byPlace: (String, String) -> Bool = { [nodes = self.nodes] a, b in
            let x = nodes[a]!, y = nodes[b]!
            return (x.order, x.started, x.id) < (y.order, y.started, y.id)
        }
        top.sort(by: byPlace)
        for key in children.keys { children[key]?.sort(by: byPlace) }
        for id in top { markShown(id) }
    }

    @discardableResult
    private mutating func markShown(_ id: String) -> Bool {
        var any = nodes[id]?.open ?? false
        for child in children[id] ?? [] where markShown(child) { any = true }
        if any { shown.insert(id) }
        return any
    }

    private static func loops(from id: String, in nodes: [String: Node]) -> Bool {
        var seen: Set<String> = [id]
        var current = nodes[id]?.parent
        while let parent = current, nodes[parent] != nil {
            guard seen.insert(parent).inserted else { return true }
            current = nodes[parent]?.parent
        }
        return false
    }

    /// The parent it sits under: nil at the top level.
    public func parent(of id: String) -> String? { parents[id] }

    /// Its sessions, in their order, shown or not.
    public func children(of id: String) -> [String] { children[id] ?? [] }

    /// The grid's cards, in order: top-level sessions that are open, or closed with an open session under them.
    public var roots: [String] { top.filter(shown.contains) }

    /// Shown on the grid or in a team: open, or closed with an open session under it.
    public func isShown(_ id: String) -> Bool { shown.contains(id) }

    /// The shown sessions under it, depth first, each with its depth.
    public func rows(under id: String) -> [Row] {
        var rows: [Row] = []
        func walk(_ parent: String, _ depth: Int) {
            for child in children[parent] ?? [] where shown.contains(child) {
                rows.append(Row(id: child, depth: depth))
                walk(child, depth + 1)
            }
        }
        walk(id, 1)
        return rows
    }

    /// Every session under it, shown or not, depth first.
    public func descendants(of id: String) -> [String] {
        (children[id] ?? []).flatMap { [$0] + descendants(of: $0) }
    }

    /// Its parent, its parent's parent, up to the top.
    public func ancestors(of id: String) -> [String] {
        var result: [String] = []
        var current = parents[id]
        while let parent = current {
            result.append(parent)
            current = parents[parent]
        }
        return result
    }

    /// The top-level session of its team: itself at the top.
    public func root(of id: String) -> String { ancestors(of: id).last ?? id }

    /// Whether it can go under `target`: never under itself or a session of its own team below it.
    public func canMove(_ id: String, under target: String) -> Bool {
        id != target && nodes[target] != nil && !descendants(of: id).contains(target)
    }
}
