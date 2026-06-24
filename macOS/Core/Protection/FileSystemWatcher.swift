import CoreServices
import Foundation

/// One filesystem change reported by `FileSystemWatcher`.
struct RealtimeFileEvent: Sendable, Hashable {
    let path: String
    let rawFlags: UInt32

    var isCreated: Bool  { rawFlags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
    var isRemoved: Bool  { rawFlags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
    var isRenamed: Bool  { rawFlags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
    var isModified: Bool { rawFlags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }
    var isFile: Bool     { rawFlags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 }
    var isDir: Bool      { rawFlags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 }
}

/// Thin Swift wrapper over an `FSEventStream`. Watches a set of directory
/// roots recursively with file-level granularity and forwards batched
/// events to a `@Sendable` handler on a background queue.
///
/// `@unchecked Sendable`: all stream mutation happens on `queue` or the
/// owning actor; the C callback only reads `handler`, which is immutable
/// after `init`.
final class FileSystemWatcher: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.dong.MacCleaner.fswatch", qos: .utility)
    private let handler: @Sendable ([RealtimeFileEvent]) -> Void

    init(handler: @escaping @Sendable ([RealtimeFileEvent]) -> Void) {
        self.handler = handler
    }

    deinit { stopStream() }

    /// (Re)starts the stream watching `paths`. Existing paths that don't
    /// exist yet are skipped — FSEvents rejects a non-existent root.
    func start(paths: [String]) {
        queue.async { [weak self] in self?.restart(paths: paths) }
    }

    func stop() {
        queue.async { [weak self] in self?.stopStream() }
    }

    fileprivate func deliver(_ events: [RealtimeFileEvent]) {
        handler(events)
    }

    // MARK: - Stream lifecycle (always on `queue`)

    private func restart(paths: [String]) {
        stopStream()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            mcFSEventsCallback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,          // coalescing latency (seconds)
            flags
        ) else {
            Log.scanner.error("FSEventStreamCreate failed for \(existing.count, privacy: .public) paths")
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        Log.scanner.info("Realtime watcher armed on \(existing.count, privacy: .public) paths")
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Top-level `@convention(c)` trampoline — FSEvents can't carry a Swift
/// closure, so we recover the watcher from the `info` pointer.
private func mcFSEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()

    // kFSEventStreamCreateFlagUseCFTypes → eventPaths is a CFArray<CFString>,
    // toll-free bridged to NSArray.
    let nsPaths = unsafeBitCast(eventPaths, to: NSArray.self)
    guard let paths = nsPaths as? [String], paths.count == numEvents else {
        return
    }
    var events: [RealtimeFileEvent] = []
    events.reserveCapacity(numEvents)
    for i in 0..<numEvents {
        events.append(RealtimeFileEvent(path: paths[i], rawFlags: eventFlags[i]))
    }
    watcher.deliver(events)
}
