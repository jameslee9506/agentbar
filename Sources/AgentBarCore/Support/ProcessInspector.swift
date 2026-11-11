import Darwin
import Foundation

/// Identifies a same-user process without reading its arguments or environment.
public struct ProcessSummary: Sendable, Equatable {
    public let pid: Int32
    public let parentPID: Int32
    public let name: String
    public let startTime: Date

    /// Creates a process summary, including its identity across PID reuse.
    public init(pid: Int32, parentPID: Int32, name: String, startTime: Date) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.startTime = startTime
    }
}

/// Contains the inspected arguments, environment, and location of one process.
public struct RunningProcess: Sendable, Equatable {
    public let pid: Int32
    public let parentPID: Int32
    public let executablePath: String
    public let arguments: [String]
    /// May be empty when macOS omits the environment of a protected process.
    public let environment: [String: String]
    public let workingDirectory: String?
    public let startTime: Date

    /// Creates a detailed process snapshot without retaining OS resources.
    public init(
        pid: Int32,
        parentPID: Int32,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        startTime: Date
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.startTime = startTime
    }
}

/// Provides best-effort, read-only inspection of processes owned by the current user.
public protocol ProcessListing: Sendable {
    /// Lists inexpensive process snapshots, skipping inaccessible processes.
    func summaries() -> [ProcessSummary]
    /// Reads one process, returning nil when it disappears or cannot be inspected.
    func details(for pid: Int32) -> RunningProcess?
    /// Returns the regular files held open by a process, when available.
    func openFilePaths(of pid: Int32) -> [String]
    /// Checks liveness and, when supplied, the start time to reject reused PIDs.
    func isAlive(_ pid: Int32, startedAt: Date?) -> Bool
}

/// Inspects same-user processes directly through libproc and KERN_PROCARGS2.
public struct SystemProcessInspector: ProcessListing {
    /// Creates a stateless process inspector.
    public init() {}

    public func summaries() -> [ProcessSummary] {
        let required = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard required > 0 else { return [] }
        var capacity = Int(required) / MemoryLayout<Int32>.stride + 64
        for _ in 0..<3 {
            var pids = [Int32](repeating: 0, count: capacity)
            let received = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(UInt32(PROC_UID_ONLY), getuid(), buffer.baseAddress, Int32(buffer.count))
            }
            guard received > 0 else { return [] }
            let count = min(Int(received) / MemoryLayout<Int32>.stride, capacity)
            if count == capacity {
                capacity *= 2
                continue
            }
            return pids.prefix(count).compactMap { pid in
                guard let info = ownedInfo(for: pid) else { return nil }
                let name = string(from: info.pbi_name)
                return ProcessSummary(
                    pid: pid,
                    parentPID: Int32(info.pbi_ppid),
                    name: name.isEmpty ? string(from: info.pbi_comm) : name,
                    startTime: startTime(of: info)
                )
            }
        }
        return []
    }

    public func details(for pid: Int32) -> RunningProcess? {
        guard let info = ownedInfo(for: pid), let arguments = arguments(for: pid) else { return nil }
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = path.withUnsafeMutableBytes { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        guard pathLength > 0 else { return nil }

        var location = proc_vnodepathinfo()
        let locationSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let hasLocation = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &location, locationSize) == locationSize
        let directory = hasLocation ? string(from: location.pvi_cdir.vip_path) : ""
        guard let current = ownedInfo(for: pid), sameStart(info, current) else { return nil }
        return RunningProcess(
            pid: pid,
            parentPID: Int32(info.pbi_ppid),
            executablePath: String(decoding: path.prefix { $0 != 0 }, as: UTF8.self),
            arguments: arguments.values,
            environment: arguments.environment,
            workingDirectory: directory.isEmpty ? nil : directory,
            startTime: startTime(of: info)
        )
    }

    public func openFilePaths(of pid: Int32) -> [String] {
        guard let initial = ownedInfo(for: pid) else { return [] }
        let required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(required) / stride + 32)
        let received = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard received > 0 else { return [] }
        var paths = Set<String>()
        for descriptor in descriptors.prefix(min(Int(received) / stride, descriptors.count))
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size,
                  (mode_t(info.pvip.vip_vi.vi_stat.vst_mode) & S_IFMT) == S_IFREG
            else { continue }
            let path = string(from: info.pvip.vip_path)
            if !path.isEmpty { paths.insert(path) }
        }
        guard let current = ownedInfo(for: pid), sameStart(initial, current) else { return [] }
        return paths.sorted()
    }

    public func isAlive(_ pid: Int32, startedAt: Date? = nil) -> Bool {
        guard let info = ownedInfo(for: pid) else { return false }
        return startedAt.map { startTime(of: info) == $0 } ?? true
    }

    private func ownedInfo(for pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB)
        else { return nil }
        return info
    }

    private func startTime(of info: proc_bsdinfo) -> Date {
        Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    private func sameStart(_ first: proc_bsdinfo, _ second: proc_bsdinfo) -> Bool {
        first.pbi_start_tvsec == second.pbi_start_tvsec && first.pbi_start_tvusec == second.pbi_start_tvusec
    }

    private func string<T>(from value: T) -> String {
        withUnsafeBytes(of: value) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private func arguments(for pid: Int32) -> (values: [String], environment: [String: String])? {
        var maximum: Int32 = 0
        var maximumSize = MemoryLayout<Int32>.size
        var maximumMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&maximumMIB, 2, &maximum, &maximumSize, nil, 0) == 0, maximum > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(maximum))
        var size = bytes.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctl(&mib, 3, buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0, size > MemoryLayout<Int32>.size else { return nil }
        return bytes.withUnsafeBytes { storage in
            let buffer = UnsafeRawBufferPointer(rebasing: storage[..<size])
            let argumentCount = buffer.loadUnaligned(as: Int32.self)
            guard argumentCount > 0, Int(argumentCount) < size else { return nil }
            var cursor = MemoryLayout<Int32>.size
            func nextString() -> String? {
                guard cursor < size, let base = buffer.baseAddress,
                      let terminator = memchr(base.advanced(by: cursor), 0, size - cursor)
                else { return nil }
                let end = base.distance(to: UnsafeRawPointer(terminator))
                let value = String(decoding: buffer[cursor..<end], as: UTF8.self)
                cursor = end + 1
                return value
            }
            guard nextString() != nil else { return nil }
            while cursor < size, buffer[cursor] == 0 { cursor += 1 }
            var values: [String] = []
            values.reserveCapacity(Int(argumentCount))
            for _ in 0..<argumentCount {
                guard let value = nextString() else { return nil }
                values.append(value)
            }
            var environment: [String: String] = [:]
            while cursor < size, buffer[cursor] != 0 {
                guard let entry = nextString() else { break }
                if let separator = entry.firstIndex(of: "=") {
                    environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
                }
            }
            return (values, environment)
        }
    }
}
