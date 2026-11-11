import Foundation

/// One line naming an item for Claude in a terminal, what Copy and a drag to another app give (T-348):
/// its kind, its key and its title. `Task T-12: Retry budget`, `PR acme/registry#418: Retry budget`.
public enum ItemLine {
    public static func line(_ kind: String, _ key: String, _ title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty || title == key ? "\(kind) \(key)" : "\(kind) \(key): \(title)"
    }

    /// A note by the name `hq file show` takes: its path inside hq/files, without `.md`.
    public static func file(_ path: String) -> String {
        "File \"\(path.hasSuffix(".md") ? String(path.dropLast(3)) : path)\""
    }

    /// "PR" or "Issue", and `owner/repo#418`, from a GitHub address; nil for any other page.
    public static func github(_ url: String) -> (kind: String, key: String)? {
        guard let address = URL(string: url), address.host() == "github.com" else { return nil }
        let parts = address.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, let number = Int(parts[3]), ["pull", "issues"].contains(parts[2]) else { return nil }
        return (parts[2] == "pull" ? "PR" : "Issue", "\(parts[0])/\(parts[1])#\(number)")
    }
}
