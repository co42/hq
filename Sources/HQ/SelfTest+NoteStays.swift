import Foundation
import HQKit

/// T-805: a Delete whose note can't go to the Trash keeps its item, says so, and logs why.
extension SelfTest {
    static func noteStaysChecks(_ model: AppModel) async {
        func lock(_ path: String?, _ locked: Bool) {
            if let path { try? FileManager.default.setAttributes([.immutable: locked], ofItemAtPath: path) }
        }
        func onDisk(_ path: String?) -> Bool { path.map(FileManager.default.fileExists) ?? false }
        guard let parent = model.addTask(status: .todo, title: "Locked story"),
              let child = model.addSubtask(to: parent.id, title: "Locked note") else {
            return check("tasks for the locked note checks", false)
        }
        lock(child.path, true)
        AppLog.expected += ["trash: \(child.path ?? "-") stayed", "trash: \(child.path ?? "-") stayed"]
        let refused = agent("task delete", ["task": parent.key, "yes": "true"])
        let error = refused["error"] as? JSONObject
        check("task delete fails when a note stays: an error that names it, nothing deleted",
              error?["code"] as? String == "failed" && (error?["message"] as? String)?.contains(child.path ?? "-") == true
              && model.task(parent.id) != nil && model.task(child.id) != nil, "\(refused)")
        check("and the notes that went come back: none is left half deleted", onDisk(parent.path) && onDisk(child.path))
        let alerts = model.ghosttyLog.count
        model.deleteTasks([parent.id])
        check("Delete in HQ keeps them too, and an alert says why",
              model.task(parent.id) != nil && model.task(child.id) != nil && onDisk(parent.path)
              && model.ghosttyLog.dropFirst(alerts).contains { $0.hasPrefix("note stayed \(parent.key) and 1 more") },
              "\(model.ghosttyLog.suffix(2))")
        lock(child.path, false)
        model.deleteTasks([parent.id])
        check("unlocked, they go", model.task(parent.id) == nil && !onDisk(child.path))

        if let file = model.addFile(title: "Locked file") {
            lock(file.path, true)
            AppLog.expected.append("trash: \(file.path ?? "-") stayed")
            let failed = agent("file delete", ["file": file.id, "yes": "true"])
            check("file delete fails when its note stays, and the file stays", (failed["error"] as? JSONObject)?["code"] as? String == "failed"
                  && model.file(file.id) != nil, "\(failed)")
            lock(file.path, false)
            model.deleteFile(file.id)
        }

        let role = model.newRole(named: "Locked Role")
        lock(role.path, true)
        AppLog.expected.append("trash: \(role.path ?? "-") stayed")
        let alertsBefore = model.ghosttyLog.count
        model.deleteRole(role.name)
        check("Delete on a role whose note stays keeps it, with an alert", model.role(named: role.name) != nil
              && model.ghosttyLog.dropFirst(alertsBefore).contains { $0.hasPrefix("note stayed Role \(role.name)") })
        lock(role.path, false)
        model.deleteRole(role.name)
        check("a note already gone deletes as asked", { () -> Bool in
            guard let gone = model.addTask(status: .todo, title: "Gone already"), let path = gone.path else { return false }
            try? FileManager.default.removeItem(atPath: path)
            return model.deleteTasks([gone.id]) == nil && model.task(gone.id) == nil
        }())
    }
}
