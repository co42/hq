import AppKit
import HQKit

/// Teams (T-406): a session another one starts sits under it; Move Under and Make Root with Undo; a closed parent stays
/// while its team runs; /clear keeps the team; Start a Session with a parent, a role and a history.
extension SelfTest {
    static func teamChecks(_ model: AppModel) async {
        let lead = "7ea70000-0000-4000-8000-0000000000a1", worker = "7ea70000-0000-4000-8000-0000000000a2"
        let helper = "7ea70000-0000-4000-8000-0000000000a3"
        for (id, name) in [(lead, "Team lead"), (worker, "Team worker"), (helper, "Team helper")] {
            model.put(SessionItem(id: id, customName: name, status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                                  repo: "team", branch: "main", started: .now, order: model.nextGridOrder))
        }
        await UITest.endUndoGroup(model)
        model.setParent(worker, to: lead)
        model.setParent(helper, to: worker)
        check("a session moved under another sits in its team, not on the grid",
              model.team(of: lead).map(\.session.id) == [worker, helper] && model.team(of: lead).map(\.depth) == [1, 2]
              && model.gridRoots.contains { $0.id == lead } && !model.gridRoots.contains { $0.id == worker },
              "\(model.team(of: lead).map { "\($0.session.name) \($0.depth)" })")
        model.setParent(lead, to: helper)
        check("never under a session of its own team", model.session(lead)?.parent == nil)
        await UITest.endUndoGroup(model)
        model.setParent(helper, to: nil)
        check("Make Root puts it on the grid right after its team",
              model.gridRoots.firstIndex { $0.id == helper } == model.gridRoots.firstIndex { $0.id == lead }.map { $0 + 1 },
              "\(model.gridRoots.map(\.name))")
        model.undoManager?.undo()
        await expect("and Undo puts it back under", model.session(helper)?.parent == worker)

        // A place among a parent's sessions (T-437): before a sibling, its siblings renumbered, one Undo for all of them.
        let aid = "7ea70000-0000-4000-8000-0000000000a4"
        model.put(SessionItem(id: aid, customName: "Team aid", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                              repo: "team", branch: "main", started: .now, order: model.nextGridOrder))
        await UITest.endUndoGroup(model)
        let grid = model.gridRoots.map(\.id)
        check("a session placed before another under a parent sits there, its parent's sessions in that order",
              model.placeSession(aid, at: SessionPlace(parent: lead, before: worker)) && model.team(of: lead).map(\.session.id) == [aid, worker, helper]
              && model.undoManager?.undoActionName == "Move Under", "\(model.team(of: lead).map(\.session.name))")
        check("placed where it already is, nothing changes", !model.placeSession(aid, at: SessionPlace(parent: lead, before: worker)))
        check("never into its own team", !model.placeSession(lead, at: SessionPlace(parent: helper)) && model.session(lead)?.parent == nil)
        await UITest.endUndoGroup(model)
        model.undoManager?.undo()
        await expect("and one Undo puts it back on the grid, in its place", model.session(aid)?.parent == nil && model.gridRoots.map(\.id) == grid)
        model.sessions.removeAll { $0.id == aid }

        // The lead's Claude ends: its card stays, faded, while its team runs; it leaves with the last one.
        func end(_ id: String) {
            guard var item = model.session(id) else { return }
            var live = item.live
            live.end(.now)
            item.live = live
            item.pid = nil
            item.closedAt = .now
            model.put(item)
        }
        end(lead)
        check("a closed parent stays on the grid while a session of its team runs",
              model.gridRoots.contains { $0.id == lead } && !model.closedSessions.contains { $0.id == lead })
        end(worker)
        check("as does a closed session between", model.team(of: lead).map(\.session.id) == [worker, helper])
        end(helper)
        check("and both leave with the last one, for Closed Sessions", !model.gridRoots.contains { $0.id == lead }
              && [lead, worker, helper].allSatisfy { id in model.closedSessions.contains { $0.id == id } })

        // /clear in a parent: the new conversation leads its team, with the role it had.
        let parent = "7ea70000-0000-4000-8000-0000000000b1", child = "7ea70000-0000-4000-8000-0000000000b2"
        let cleared = "7ea70000-0000-4000-8000-0000000000b3", pid: Int32 = 999_901
        for id in [parent, child] {
            model.put(SessionItem(id: id, customName: id == parent ? "Clear lead" : "Clear worker", status: SessionStatus(state: .idle, since: .now),
                                  cwd: NSTemporaryDirectory(), repo: "team", branch: "main", started: .now, pid: id == parent ? pid : nil,
                                  order: model.nextGridOrder, parent: id == child ? parent : nil, role: id == parent ? "Leader" : "Worker"))
        }
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
        agent("hook", ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(cleared)\",\"cwd\":\"\(NSTemporaryDirectory())\",\"source\":\"clear\"}",
                       "pid": "\(pid)"])
        check("after /clear the session keeps its role and leads its team",
              model.session(cleared)?.role == "Leader" && model.session(child)?.parent == cleared,
              "\(String(describing: model.session(cleared)?.role)), \(String(describing: model.session(child)?.parent))")
        model.exitWatchers.removeValue(forKey: pid)?.cancel()

        // Start a Session under a parent, with a role and another session's history.
        let log = model.ghosttyLog.count
        let started = model.startSession(named: "Team child", in: NSTemporaryDirectory(), parent: cleared, role: "Worker", history: child)
        check("Start a Session under a parent: in its team, with its role and that history",
              model.session(started)?.parent == cleared && model.session(started)?.role == "Worker"
              && model.ghosttyLog.count == log + 1 && model.ghosttyLog.last?.contains("claude --resume \(child) --fork-session --session-id \(started)") == true,
              model.ghosttyLog.last ?? "-")
        model.sessions.removeAll { [lead, worker, helper, parent, child, cleared, started].contains($0.id) }
    }
}
