import Foundation

/// Claude Code's version: a running Claude's, from where its executable lives (`…/claude/versions/2.1.325`), and the
/// installed one, from where `~/.local/bin/claude` points (T-454).
public enum ClaudeVersion {
    /// The version in an installed Claude's path, or nil.
    public static func inPath(_ path: String) -> String? {
        guard let range = path.range(of: "/claude/versions/") else { return nil }
        let version = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        return version.first?.isNumber == true ? version : nil
    }

    /// The version a running Claude runs.
    public static func running(_ pid: Int32) -> String? {
        ClaudeProcess.path(of: pid).flatMap(inPath)
    }

    /// The version `claude` starts now: where its link points.
    public static func installed(link: String = NSHomeDirectory() + "/.local/bin/claude") -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return nil }
        return inPath(target)
    }

    /// `a` is older than `b`, number by number: 2.1.99 < 2.1.325.
    public static func isOlder(_ a: String, than b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }, right = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0, y = index < right.count ? right[index] : 0
            if x != y { return x < y }
        }
        return false
    }
}
