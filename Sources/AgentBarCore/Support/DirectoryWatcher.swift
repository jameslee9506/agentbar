import CoreServices
import Foundation

/// Watches directory trees and delivers coalesced batches of absolute changed paths.
public final class DirectoryWatcher: Sendable {
    /// Reports invalid watch configuration or failure to register with FSEvents.
    public enum WatchError: Error, Sendable {
        case invalidConfiguration
        case creationFailed
        case startFailed
    }

    /// A single-consumer stream whose cancellation stops the underlying watch.
    public let events: AsyncStream<[String]>
    private let lifetime: StreamLifetime

    /// Starts recursive file-level watching, including roots that do not exist yet.
    public init(directories: [URL], latency: TimeInterval = 0.1) throws {
        guard !directories.isEmpty, directories.allSatisfy(\.isFileURL),
              latency.isFinite, latency >= 0
        else { throw WatchError.invalidConfiguration }
        let roots = Array(Set(directories.map(normalizedWatchPath))).sorted()
        let watchedPaths = Array(Set(roots.map(Self.existingAncestor))).sorted()
        let (events, continuation) = AsyncStream<[String]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        let sink = EventSink(roots: roots, continuation: continuation)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<EventSink>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                if let pointer { Unmanaged<EventSink>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        let stream = withExtendedLifetime(sink) {
            FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, context, count, paths, flags, _ in
                    guard let context else { return }
                    Unmanaged<EventSink>.fromOpaque(context).takeUnretainedValue()
                        .receive(count: count, paths: paths, flags: flags)
                },
                &context,
                watchedPaths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
            )
        }
        guard let stream else {
            continuation.finish()
            throw WatchError.creationFailed
        }
        let queue = DispatchQueue(label: "dev.agentbar.directory-watcher", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            continuation.finish()
            throw WatchError.startFailed
        }
        let lifetime = StreamLifetime(stream: stream, queue: queue, continuation: continuation)
        self.lifetime = lifetime
        continuation.onTermination = { [weak lifetime] _ in lifetime?.stop() }
    }

    deinit {
        lifetime.stop()
    }

    /// Stops watching and finishes the stream; repeated calls are harmless.
    public func stop() {
        lifetime.stop()
    }

    private static func existingAncestor(of path: String) -> String {
        var ancestor = URL(fileURLWithPath: path).deletingLastPathComponent()
        while ancestor.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory), isDirectory.boolValue {
                break
            }
            ancestor.deleteLastPathComponent()
        }
        return ancestor.path
    }
}

private final class EventSink: Sendable {
    let roots: [String]
    let continuation: AsyncStream<[String]>.Continuation

    init(roots: [String], continuation: AsyncStream<[String]>.Continuation) {
        self.roots = roots
        self.continuation = continuation
    }

    func receive(count: Int, paths: UnsafeMutableRawPointer, flags: UnsafePointer<FSEventStreamEventFlags>) {
        let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        var changes = Set<String>()
        for index in 0..<count {
            let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
            if flags[index] & dropped != 0 {
                changes.formUnion(roots)
                continue
            }
            let path = normalizedWatchPath(URL(fileURLWithPath: String(cString: paths[index])))
            for root in roots {
                if contains(path, in: root) {
                    changes.insert(path)
                } else if contains(root, in: path) {
                    changes.insert(root)
                }
            }
        }
        guard !changes.isEmpty else { return }
        if case .dropped(let previous) = continuation.yield(changes.sorted()) {
            changes.formUnion(previous)
            continuation.yield(changes.sorted())
        }
    }

    private func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
}

private func normalizedWatchPath(_ url: URL) -> String {
    var ancestor = url.standardizedFileURL
    var missingComponents: [String] = []
    while ancestor.path != "/", !FileManager.default.fileExists(atPath: ancestor.path) {
        missingComponents.append(ancestor.lastPathComponent)
        ancestor.deleteLastPathComponent()
    }
    var resolved = ancestor.resolvingSymlinksInPath()
    for component in missingComponents.reversed() {
        resolved.appendPathComponent(component)
    }
    return resolved.path
}

private final class StreamLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let continuation: AsyncStream<[String]>.Continuation

    init(stream: FSEventStreamRef, queue: DispatchQueue, continuation: AsyncStream<[String]>.Continuation) {
        self.stream = stream
        self.queue = queue
        self.continuation = continuation
    }

    func stop() {
        let stream = lock.withLock {
            let current = self.stream
            self.stream = nil
            return current
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        continuation.finish()
    }
}
