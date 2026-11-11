import Foundation

/// What a waiting session needs from the user.
public enum WaitReason: String, Sendable, Hashable, CaseIterable {
    case permission, question, plan
}

/// A session's live state, as the hook events set it (PLAN.md §6).
public enum SessionState: Sendable, Hashable {
    case waiting(WaitReason)
    case failed
    case done
    case working
    case compacting
    case idle
    case ended
}

/// A session's state with when it began.
public struct SessionStatus: Sendable, Hashable {
    public var state: SessionState
    /// Done and not yet opened from HQ.
    public var unread: Bool
    /// When the current state began.
    public var since: Date
    public var lastActivity: Date

    public init(state: SessionState, unread: Bool = false, since: Date, lastActivity: Date? = nil) {
        self.state = state
        self.unread = unread
        self.since = since
        self.lastActivity = lastActivity ?? since
    }

    /// Orange (red when failed): the session waits on the user.
    public var needsYou: Bool {
        switch state {
        case .waiting, .failed: true
        default: false
        }
    }

    /// Blue: done since the user last looked.
    public var isNew: Bool { state == .done && unread }

    public var isEnded: Bool { state == .ended }

    /// "Working", "Asks", "Plan ready", … for state lines and VoiceOver.
    public var title: String {
        switch state {
        case .waiting(.permission): "Wants permission"
        case .waiting(.question): "Asks"
        case .waiting(.plan): "Plan ready"
        case .failed: "Failed"
        case .done: "Done"
        case .working: "Working"
        case .compacting: "Compacting"
        case .idle: "Idle"
        case .ended: "Ended"
        }
    }
}

/// Short elapsed times for rows: "<1m", "4m", "2h", "3d", "2w".
public enum Elapsed {
    public static func short(from start: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 14 { return "\(days)d" }
        return "\(days / 7)w"
    }

    /// Spoken form for VoiceOver: "4 minutes".
    public static func spoken(from start: Date, to now: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth]
        return formatter.string(from: max(60, now.timeIntervalSince(start))) ?? ""
    }
}
