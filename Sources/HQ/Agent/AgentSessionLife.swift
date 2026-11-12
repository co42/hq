import Foundation
import HQKit

// A team's sessions closed and resumed from hq (T-450): only the sessions under the caller, at any depth.
extension AgentCommands {
    static func closeSessionCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let session = try sessionUnderCaller(args, model, "close")
        let short = session.id.prefix(8)
        guard session.closedAt == nil else {
            throw AgentError.invalid("“\(session.name)” (\(short)) is closed already: hq session resume \(short) brings it back")
        }
        if session.isRunning, case .waiting = session.status.state {
            throw AgentError.invalid("“\(session.name)” (\(short)) waits on the user: \(session.reason ?? session.stateWords). hq types nothing into "
                                     + "its prompt: the user answers it or presses Esc in its terminal, then close it")
        }
        let note: String
        if !session.isRunning {
            note = "“\(session.name)” had ended: it's in Closed Sessions now. hq session resume \(short) brings it back"
        } else if model.neverReported(session) {
            note = "“\(session.name)” never started: it's gone, with nothing to resume"
        } else if model.backgroundHandles[session.id] != nil {
            note = "Stopping “\(session.name)” with claude stop. Its conversation stays: hq session resume \(short) brings it back"
        } else {
            let working = session.status.state == .working || session.status.state == .compacting
            note = "Closing “\(session.name)”: \(working ? "Escape to stop its turn, then " : "")its input emptied and /exit typed in its terminal, "
                + "which closes once Claude quits. Its conversation stays: hq session resume \(short) brings it back"
        }
        model.closeSession(session.id, quietly: true)
        var json = (model.session(session.id) ?? session).agentJSON(model)
        json["note"] = note
        return json
    }

    static func resumeSessionCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let session = try sessionUnderCaller(args, model, "resume")
        let short = session.id.prefix(8)
        guard !session.isRunning else {
            throw AgentError.invalid("“\(session.name)” (\(short)) is running: nothing to resume. Message it with SendMessage, to “\(session.name)”")
        }
        guard !model.neverReported(session) else {
            throw AgentError.invalid("“\(session.name)” (\(short)) never started: it has no conversation to resume. hq session new starts a fresh one")
        }
        let window = model.windowTTY(forChildOf: model.parentSession(of: session.id)?.id)
        model.resume(session.id)
        var json = (model.session(session.id) ?? session).agentJSON(model)
        json["note"] = "Resuming “\(session.name)”: claude --resume in a new tab of " + (window == nil ? "Ghostty's front window" : "its parent's Ghostty window")
            + ", its place in your team kept" + (model.role(named: session.role).map { ", its \($0.name) text sent again" } ?? "")
        return json
    }

    /// The <session> close and resume act on: one the calling session started, or one of theirs, at any depth. Anything
    /// else is refused, naming it.
    private static func sessionUnderCaller(_ args: Args, _ model: AppModel, _ verb: String) throws -> SessionItem {
        let session = try findSession(args.required("session"), model, for: "<session>")
        guard let caller = model.session(args.string(sessionArg)) else {
            throw AgentError.usage("hq session \(verb) acts on the sessions a session started: run it from that Claude session")
        }
        guard model.sessionTree.descendants(of: caller.id).contains(session.id) else {
            let place = session.id == caller.id ? "it's this session"
                : model.parentSession(of: session.id).map { "it's under “\($0.name)”" } ?? "it's at the top level"
            throw AgentError.notMine("“\(session.name)” (\(session.id.prefix(8))) isn't under this session: \(place). "
                                     + "hq session \(verb) acts only on the sessions you started and theirs (hq ctx lists them)")
        }
        return session
    }
}
