import CryptoKit
import Foundation

/// A fixed-width request identity or checkpoint fingerprint; never retains source text.
struct TranscriptHash: Hashable, Codable, Sendable {
    let low: UInt64
    let high: UInt64

    static func digest(_ data: Data) -> Self {
        digest([data])
    }

    static func digest(_ parts: [Data]) -> Self {
        var hash = SHA256()
        for data in parts { hash.update(data: data) }
        return hash.finalize().withUnsafeBytes {
            Self(low: $0.loadUnaligned(as: UInt64.self).littleEndian,
                 high: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self).littleEndian)
        }
    }
}
