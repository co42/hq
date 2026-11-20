import Foundation

extension GitHubItem {
    /// A list's PRs with each stack together (DESIGN.md §6): a stack is the PRs of one repository whose base branch is
    /// another's head, its base (merges first) on top, then each PR stacked on it, depth first. A stack sits where its
    /// first PR in `items` sat; a PR on no other is a stack of one.
    public static func stacks(_ items: [GitHubItem]) -> [[GitHubItem]] {
        struct Branch: Hashable { let repo: String, name: String }
        var byHead: [Branch: Int] = [:]
        for (index, item) in items.enumerated() {
            if let head = item.headBranch, byHead[Branch(repo: item.repo, name: head)] == nil { byHead[Branch(repo: item.repo, name: head)] = index }
        }
        func parent(_ index: Int) -> Int? {
            let item = items[index]
            guard let base = item.baseBranch, let found = byHead[Branch(repo: item.repo, name: base)], found != index else { return nil }
            return found
        }
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for index in items.indices {
            if let up = parent(index) { children[up, default: []].append(index) } else { roots.append(index) }
        }
        var placed = Set<Int>()
        func walk(_ index: Int) -> [Int] {
            guard placed.insert(index).inserted else { return [] }
            let below = (children[index] ?? []).sorted { items[$0].number < items[$1].number }
            return [index] + below.flatMap(walk)
        }
        var groups = roots.map(walk)
        // A loop of bases has no root: each of its PRs stands alone.
        groups += items.indices.filter { !placed.contains($0) }.map { [$0] }
        return groups.sorted { $0.min()! < $1.min()! }.map { $0.map { items[$0] } }
    }

    /// The PR of `stack` this one is stacked on, for "on #80".
    public func stacked(in stack: [GitHubItem]) -> GitHubItem? {
        guard let base = baseBranch else { return nil }
        return stack.first { $0.url != url && $0.repo == repo && $0.headBranch == base }
    }
}
