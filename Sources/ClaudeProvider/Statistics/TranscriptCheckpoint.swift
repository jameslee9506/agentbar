import Foundation

struct TranscriptCheckpoint: Codable, Sendable {
    let path: String
    let stamp: TranscriptFileStamp
    let offset: UInt64
    let prefixHash: TranscriptHash
    let boundaryHash: TranscriptHash

    func canAppend(file: URL, stamp next: TranscriptFileStamp) -> Bool {
        guard next.identity == stamp.identity, next.size > stamp.size, next.size >= offset,
              let guards = Self.fingerprints(file: file, offset: offset)
        else { return false }
        return guards.0 == prefixHash && guards.1 == boundaryHash
    }

    static func fingerprints(file: URL, offset: UInt64) -> (TranscriptHash, TranscriptHash)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let length = Int(min(offset, 4_096))
        do {
            let prefix = try handle.read(upToCount: length) ?? Data()
            try handle.seek(toOffset: offset - UInt64(length))
            let boundary = try handle.read(upToCount: length) ?? Data()
            guard prefix.count == length, boundary.count == length else { return nil }
            return (TranscriptHash.digest(prefix), TranscriptHash.digest(boundary))
        } catch { return nil }
    }
}
