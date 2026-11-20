import AppKit

/// Watches the main thread from a thread of its own (T-683): when it stops answering for 2 s, HQ samples itself once into
/// hang-<time>.txt beside its logs; when it answers again, hangs.log says how long it held and where its stack is.
final class HangWatch: @unchecked Sendable {
    nonisolated static let shared = HangWatch()
    nonisolated static let limit: TimeInterval = 2
    /// The hang samples kept: the oldest go.
    nonisolated static let kept = 10
    /// The stalls seen, for the self-test: how long each held and its sample.
    static var stalls: [(seconds: Double, sample: URL?)] = []

    private let lock = NSLock()
    nonisolated(unsafe) private var answered = CACurrentMediaTime()

    func start() {
        let folder = Store.isOverridden ? Store.directory : URL.libraryDirectory.appending(path: "Logs/HQ", directoryHint: .isDirectory)
        Thread.detachNewThread { [self] in watch(samplesIn: folder) }
    }

    nonisolated private func watch(samplesIn folder: URL) {
        var stalled: (since: Double, sample: URL?)?
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            DispatchQueue.main.async { [self] in lock.withLock { answered = CACurrentMediaTime() } }
            let last = lock.withLock { answered }
            let silent = CACurrentMediaTime() - last
            if stalled == nil, silent >= Self.limit {
                stalled = (last, Self.sample(in: folder))
            } else if let stall = stalled, silent < Self.limit, last > stall.since {
                stalled = nil
                let seconds = last - stall.since
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Self.stalls.append((seconds, stall.sample))
                        AppLog.write("main thread stalled \(String(format: "%.1f", seconds)) s; its stack: \(stall.sample?.path ?? "no sample")",
                                     to: "hangs.log")
                    }
                }
            }
        }
    }

    /// Two seconds of HQ's threads from sample(1), every 10 ms, written in the background: the main thread's stack while it hangs.
    nonisolated private static func sample(in folder: URL) -> URL? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("hang-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in old.dropLast(kept - 1) { try? FileManager.default.removeItem(at: file) }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let file = folder.appending(path: "hang-\(stamp).txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "10", "-mayDie", "-file", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        return file
    }
}
