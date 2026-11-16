import AppKit

/// A file's text as last read in the background, and the version it was read for.
nonisolated struct DiskText: Equatable, Sendable {
    var text: String
    var version: Date
}

/// The one serial queue every note write runs on: in order, off the main thread.
nonisolated enum NoteWriter {
    static let queue = DispatchQueue(label: "hq.note-writer", qos: .userInitiated)

    static func run(_ write: @escaping @Sendable () throws -> Void, then done: @escaping @Sendable (String?) -> Void) {
        queue.async {
            var failure: String?
            do { try write() } catch { failure = "\(error)" }
            done(failure)
        }
    }
}

/// Notes and plans are read and written off the main thread (T-486): a view shows LoadingLine until its text is in.
extension AppModel {
    /// Reads `path` in the background, unless its text for `version` is in or a write to it is queued (the text in is newer).
    func readDiskText(_ path: String, version: Date, read: @escaping @Sendable (String) -> String) async {
        if let have = diskTexts[path], have.version >= version || pendingWrites[path] != nil { return }
        let text = await Task.detached(priority: .userInitiated) { read(path) }.value
        guard pendingWrites[path] == nil, (diskTexts[path]?.version ?? .distantPast) <= version else { return }
        diskTexts[path] = DiskText(text: text, version: version)
    }

    /// A note's write on the background writer. Until it lands, a vault scan keeps HQ's copy of the note.
    func writeNote(_ path: String?, _ write: @escaping @Sendable () throws -> Void) {
        if let path { pendingWrites[path, default: 0] += 1 }
        NoteWriter.run(write) { [weak self] failure in
            Task { @MainActor in self?.noteWritten(path, failure: failure) }
        }
    }

    /// One job on the background writer for several notes (a story moving to or from the Archive): until it lands, a
    /// vault scan keeps HQ's copy of each.
    func writeNotes(_ paths: [String], _ write: @escaping @Sendable () throws -> Void) {
        for path in paths { pendingWrites[path, default: 0] += 1 }
        NoteWriter.run(write) { [weak self] failure in
            Task { @MainActor in
                for (index, path) in paths.enumerated() { self?.noteWritten(path, failure: index == 0 ? failure : nil) }
            }
        }
    }

    private func noteWritten(_ path: String?, failure: String?) {
        if let path {
            vaultWrites[path] = .now
            pendingWrites[path] = (pendingWrites[path] ?? 1) > 1 ? pendingWrites[path]! - 1 : nil
        }
        if let failure {
            NSSound.beep()
            AppLog.write("couldn't write a note: \(failure)", to: "vault.log")
        }
    }

    /// Waits for the queued note writes: before quitting, and in a check that reads a note back.
    func flushNoteWrites() {
        NoteWriter.queue.sync {} // io: ok waits for the writes before quitting or a check reads a note
    }
}
