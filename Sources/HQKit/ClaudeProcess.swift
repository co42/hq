import Darwin
import Foundation

/// Where a Claude Code process runs, read from the kernel (no `ps`).
public enum ClaudeProcess {
    public struct Info: Sendable, Equatable {
        public var pid: Int32
        public var tty: String?
        public var inGhostty: Bool
    }

    /// The Claude that runs this hook: `CLAUDE_PID`, else the nearest ancestor that is Claude.
    public static func current(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Info? {
        let pid = environment["CLAUDE_PID"].flatMap(Int32.init) ?? ancestors(of: getpid()).first(where: isClaude)
        guard let pid else { return nil }
        return Info(pid: pid, tty: tty(of: pid),
                    inGhostty: ancestors(of: pid).contains { path(of: $0)?.contains("/Ghostty.app/") == true })
    }

    /// True while `pid` is a running Claude: a pid that was reused by something else doesn't count.
    public static func isRunningClaude(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 && isClaude(pid)
    }

    /// Claude Code installs as `…/claude/versions/<version>`, or runs as `claude`.
    static func isClaude(_ pid: Int32) -> Bool {
        guard let path = path(of: pid) else { return false }
        return path.contains("/claude/versions/") || (path as NSString).lastPathComponent == "claude"
    }

    /// Parents up to launchd. Through sysctl, as `ps` does: it also reads root's processes,
    /// like the `login` between Ghostty and the shell.
    static func ancestors(of pid: Int32) -> [Int32] {
        var chain: [Int32] = []
        var current = pid
        while let parent = kernel(current)?.kp_eproc.e_ppid, parent > 1, chain.count < 32 {
            chain.append(parent)
            current = parent
        }
        return chain
    }

    static func path(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    static func tty(of pid: Int32) -> String? {
        guard let device = kernel(pid)?.kp_eproc.e_tdev, device != -1,
              let name = devname(device, mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func kernel(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
