import AgentBarCore
import Darwin
import Foundation

struct TranscriptParser {
    private struct Row: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_read_input_tokens: Int?
                let cache_creation_input_tokens: Int?
            }
            let id: String?
            let model: String?
            let stop_reason: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let uuid: String?
        let isSidechain: Bool?
        let message: Message?
    }

    private let decoder = JSONDecoder()

    func parse(_ bytes: UnsafeRawBufferPointer, fileIdentity: TranscriptFileStamp.Identity,
               file: UInt32, offset: UInt64) -> (TranscriptHash, String, TranscriptUsage)? {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return nil }
        let hasUsage = "\"usage\"".withCString { memmem(base, bytes.count, $0, 7) != nil }
        guard hasUsage else { return nil }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count, deallocator: .none)
        guard let row = try? decoder.decode(Row.self, from: data), row.type == "assistant",
              let message = row.message, let model = message.model, model != "<synthetic>", !model.isEmpty,
              let usage = message.usage, let timestamp = row.timestamp.flatMap(Timestamps.parse),
              usage.input_tokens != nil || usage.output_tokens != nil
                || usage.cache_read_input_tokens != nil || usage.cache_creation_input_tokens != nil
        else { return nil }
        let key: String
        if let id = message.id, !id.isEmpty {
            key = "m:" + id
        } else if let uuid = row.uuid, !uuid.isEmpty {
            key = "u:" + uuid
        } else {
            key = "f:\(fileIdentity.device):\(fileIdentity.inode):\(offset)"
        }
        return (TranscriptHash.digest(Data(key.utf8)), model, TranscriptUsage(
            timestamp: timestamp,
            tokens: TokenCount(input: max(0, usage.input_tokens ?? 0), output: max(0, usage.output_tokens ?? 0),
                               cacheRead: max(0, usage.cache_read_input_tokens ?? 0),
                               cacheWrite: max(0, usage.cache_creation_input_tokens ?? 0)),
            offset: offset, file: file, model: 0,
            flags: (message.stop_reason != nil ? 1 : 0) | (row.isSidechain == true ? 2 : 0)
        ))
    }
}
