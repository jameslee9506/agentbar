import AgentBarCore
import Foundation

/// Explicit little-endian fields and lossless variable-length counters, with no struct padding.
enum TranscriptLedgerCoding {
    static func encode(_ rows: [TranscriptHash: TranscriptUsage]) -> Data {
        var data = Data(capacity: 8 + rows.count * 52)
        func fixed<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func variable(_ value: Int) {
            var value = UInt64(value)
            while value >= 128 {
                data.append(UInt8(value & 127) | 128)
                value >>= 7
            }
            data.append(UInt8(value))
        }
        fixed(UInt64(rows.count))
        for (key, row) in rows {
            fixed(key.low)
            fixed(key.high)
            fixed(row.timestamp.timeIntervalSinceReferenceDate.bitPattern)
            fixed(row.offset)
            fixed(row.file)
            fixed(row.model)
            data.append(row.flags)
            variable(row.tokens.input)
            variable(row.tokens.output)
            variable(row.tokens.cacheRead)
            variable(row.tokens.cacheWrite)
        }
        return data
    }

    static func decode(_ data: Data, files: Int, models: Int) -> [TranscriptHash: TranscriptUsage]? {
        data.withUnsafeBytes { bytes in
            var cursor = 0
            func fixed<T: FixedWidthInteger>(_ type: T.Type) -> T? {
                guard bytes.count - cursor >= MemoryLayout<T>.size else { return nil }
                defer { cursor += MemoryLayout<T>.size }
                return bytes.loadUnaligned(fromByteOffset: cursor, as: type).littleEndian
            }
            func variable() -> Int? {
                var value: UInt64 = 0
                for shift in stride(from: 0, through: 56, by: 7) {
                    guard cursor < bytes.count else { return nil }
                    let byte = bytes[cursor]
                    cursor += 1
                    value |= UInt64(byte & 127) << shift
                    if byte & 128 == 0 { return Int(exactly: value) }
                }
                return nil
            }
            guard let count = fixed(UInt64.self), count <= UInt64((bytes.count - cursor) / 45) else { return nil }
            var rows: [TranscriptHash: TranscriptUsage] = [:]
            rows.reserveCapacity(Int(count))
            for _ in 0..<count {
                guard let low = fixed(UInt64.self), let high = fixed(UInt64.self),
                      let timeBits = fixed(UInt64.self), let offset = fixed(UInt64.self),
                      let file = fixed(UInt32.self), Int(file) < files,
                      let model = fixed(UInt32.self), Int(model) < models,
                      let flags = fixed(UInt8.self), flags <= 3,
                      let input = variable(), let output = variable(), let read = variable(), let write = variable()
                else { return nil }
                let timestamp = Double(bitPattern: timeBits)
                guard timestamp.isFinite else { return nil }
                let key = TranscriptHash(low: low, high: high)
                guard rows.updateValue(TranscriptUsage(timestamp: Date(timeIntervalSinceReferenceDate: timestamp),
                    tokens: TokenCount(input: input, output: output, cacheRead: read, cacheWrite: write),
                    offset: offset, file: file, model: model, flags: flags), forKey: key) == nil else { return nil }
            }
            return cursor == bytes.count ? rows : nil
        }
    }
}
