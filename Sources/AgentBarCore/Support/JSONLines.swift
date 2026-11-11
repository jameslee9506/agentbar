import Darwin
import Foundation

/// Reads newline-delimited bytes incrementally with bounded buffers and no text decoding.
public enum JSONLines: Sendable {
    /// Reports invalid read limits.
    public enum ReadError: Error, Sendable, Equatable {
        case invalidLimit
    }

    private static let chunkBytes = 256 * 1024

    /// Visits borrowed line bytes without LF and returns the offset after the last complete LF-delimited line.
    ///
    /// Reads through one reusable buffer and drains an autorelease pool per line, so memory stays bounded
    /// for files and lines of any size. Lines longer than `maximumLineBytes` are skipped. Reading stops at
    /// `limit` when given, otherwise at the current end of the file.
    @discardableResult
    public static func forEachLine(
        in file: URL,
        fromOffset offset: UInt64 = 0,
        upTo limit: UInt64? = nil,
        maximumLineBytes: Int = 16 * 1024 * 1024,
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) throws -> UInt64 {
        guard maximumLineBytes > 0 else { throw ReadError.invalidLimit }
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let end = min(UInt64(max(info.st_size, 0)), limit ?? .max)

        var buffer = [UInt8](repeating: 0, count: chunkBytes)
        var pending = Data()
        var skipping = false
        var cursor = offset
        var completeOffset = offset
        while cursor < end {
            let length = Int(min(UInt64(chunkBytes), end - cursor))
            let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, length, off_t(cursor)) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            try buffer.withUnsafeBytes { storage in
                guard let base = storage.baseAddress else { return }
                var lineStart = 0
                while lineStart < count {
                    let remaining = count - lineStart
                    guard let newline = memchr(base.advanced(by: lineStart), 0x0A, remaining) else {
                        if skipping || remaining > maximumLineBytes - pending.count {
                            skipping = true
                            pending.removeAll(keepingCapacity: true)
                        } else {
                            pending.append(contentsOf: storage[lineStart..<count])
                        }
                        break
                    }
                    let lineEnd = base.distance(to: UnsafeRawPointer(newline))
                    let lineLength = lineEnd - lineStart
                    if skipping || lineLength > maximumLineBytes - pending.count {
                        skipping = false
                        pending.removeAll(keepingCapacity: true)
                    } else if pending.isEmpty {
                        let line = UnsafeRawBufferPointer(start: base.advanced(by: lineStart), count: lineLength)
                        try autoreleasepool { try body(line) }
                    } else {
                        pending.append(contentsOf: storage[lineStart..<lineEnd])
                        try autoreleasepool { try pending.withUnsafeBytes(body) }
                        pending.removeAll(keepingCapacity: true)
                    }
                    lineStart = lineEnd + 1
                    completeOffset = cursor + UInt64(lineStart)
                }
            }
            cursor += UInt64(count)
        }
        return completeOffset
    }

    /// Reads at most the requested number of bytes from the end, including any incomplete line.
    public static func tailBytes(in file: URL, maximumCount: Int) throws -> Data {
        guard maximumCount >= 0 else { throw ReadError.invalidLimit }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        let length = min(UInt64(maximumCount), end)
        try handle.seek(toOffset: end - length)
        return try readBytes(handle, count: Int(length))
    }

    /// Returns the last complete lines within the byte limit, omitting partial lines at either boundary.
    public static func tailLines(
        in file: URL,
        count: Int,
        maximumBytes: Int = 16 * 1024 * 1024
    ) throws -> [Data] {
        guard count >= 0, maximumBytes > 0 else { throw ReadError.invalidLimit }
        guard count > 0 else { return [] }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        let lowerBound = end - min(end, UInt64(maximumBytes))
        var cursor = end
        var newlineCount = 0
        var completeEnd: UInt64?
        var firstNewline: UInt64?
        var start: UInt64?

        while cursor > lowerBound, start == nil {
            let blockStart = cursor - min(cursor - lowerBound, UInt64(chunkBytes))
            try handle.seek(toOffset: blockStart)
            let block = try readBytes(handle, count: Int(cursor - blockStart))
            block.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for index in bytes.indices.reversed() where bytes[index] == 0x0A {
                    let position = blockStart + UInt64(index)
                    newlineCount += 1
                    firstNewline = position
                    if completeEnd == nil { completeEnd = position + 1 }
                    if newlineCount > count {
                        start = position + 1
                        break
                    }
                }
            }
            cursor = blockStart
        }
        guard let completeEnd, let firstNewline else { return [] }
        var startsAtBoundary = lowerBound == 0
        if lowerBound > 0 {
            try handle.seek(toOffset: lowerBound - 1)
            startsAtBoundary = try handle.read(upToCount: 1)?.first == 0x0A
        }
        let startOffset = start ?? (startsAtBoundary ? lowerBound : firstNewline + 1)
        var lines: [Data] = []
        try forEachLine(in: file, fromOffset: startOffset, upTo: completeEnd, maximumLineBytes: maximumBytes) {
            lines.append(Data($0))
        }
        return lines
    }

    private static func readBytes(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else { break }
            result.append(chunk)
        }
        return result
    }
}
