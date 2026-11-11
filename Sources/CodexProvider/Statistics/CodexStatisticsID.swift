import CryptoKit
import Foundation

/// Stable 128-bit identities replace retained thread, turn, and response strings.
struct CodexStatisticsID: Hashable, Comparable, Sendable {
    let first: UInt64
    let second: UInt64
    static let zero = Self(first: 0, second: 0)

    init(first: UInt64, second: UInt64) { self.first = first; self.second = second }
    init(_ string: String) { self.init(data: Data(string.utf8)) }
    init(data: Data) {
        self = SHA256.hash(data: data).withUnsafeBytes {
            Self(first: $0.loadUnaligned(as: UInt64.self), second: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
        }
    }

    func combined(with value: String) -> Self {
        var data = Data()
        withUnsafeBytes(of: first.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: second.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: value.utf8)
        return Self(data: data)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.first, lhs.second) < (rhs.first, rhs.second) }

    static func anchor(_ file: URL, endingAt offset: UInt64) -> Self? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let count = Int(min(offset, 256))
        guard (try? handle.seek(toOffset: offset - UInt64(count))) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return Self(data: data)
    }
}
