import AgentBarCore
import Darwin
import Foundation

enum TranscriptLines {
    private enum ReadError: Error { case changedDuringRead }
    private static let maximumLineBytes = 16 * 1024 * 1024

    static func scan(_ file: URL, from offset: UInt64, upTo end: UInt64,
                     _ body: (UnsafeRawBufferPointer, UInt64) throws -> Void) throws -> UInt64 {
        let offsets = try Offsets(file: file, from: offset, upTo: end)
        return try JSONLines.forEachLine(in: file, fromOffset: offset, upTo: end,
                                        maximumLineBytes: maximumLineBytes) { bytes in
            guard let line = try offsets.next(), line.length == bytes.count else { throw ReadError.changedDuringRead }
            try body(bytes, line.offset)
        }
    }

    // JSONLines omits oversized rows and does not report individual offsets. This bounded cursor
    // supplies physical positions for anonymous identities and append-order preference only.
    private final class Offsets {
        private let descriptor: Int32
        private let end: UInt64
        private var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        private var bufferStart: UInt64
        private var nextRead: UInt64
        private var lineStart: UInt64
        private var index = 0
        private var count = 0

        init(file: URL, from offset: UInt64, upTo end: UInt64) throws {
            descriptor = open(file.path, O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            self.end = end
            bufferStart = offset
            nextRead = offset
            lineStart = offset
        }

        deinit { close(descriptor) }

        func next() throws -> (offset: UInt64, length: Int)? {
            while true {
                if index == count {
                    guard nextRead < end else { return nil }
                    let length = Int(min(UInt64(buffer.count), end - nextRead))
                    count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, length, off_t(nextRead)) }
                    if count < 0, errno == EINTR { count = 0; index = 0; continue }
                    guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    guard count > 0 else { return nil }
                    bufferStart = nextRead
                    nextRead += UInt64(count)
                    index = 0
                }
                let newline = buffer.withUnsafeBytes { bytes -> Int? in
                    guard let base = bytes.baseAddress,
                          let match = memchr(base.advanced(by: index), 10, count - index) else { return nil }
                    return base.distance(to: UnsafeRawPointer(match))
                }
                guard let newline else { index = count; continue }
                index = newline + 1
                let start = lineStart
                lineStart = bufferStart + UInt64(index)
                let length = lineStart - start - 1
                if length <= maximumLineBytes { return (start, Int(length)) }
            }
        }
    }
}
