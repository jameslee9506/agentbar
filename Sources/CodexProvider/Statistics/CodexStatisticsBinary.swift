import AgentBarCore
import Foundation

enum CodexStatisticsBinary {
    enum Invalid: Error { case data }

    struct Writer {
        var data = Data()

        mutating func uint(_ value: UInt64) {
            var value = value
            while value >= 128 { data.append(UInt8(value & 127) | 128); value >>= 7 }
            data.append(UInt8(value))
        }
        mutating func int(_ value: Int64) { uint(UInt64(bitPattern: (value << 1) ^ (value >> 63))) }
        mutating func bool(_ value: Bool) { uint(value ? 1 : 0) }
        mutating func string(_ value: String) { uint(UInt64(value.utf8.count)); data.append(contentsOf: value.utf8) }
        mutating func id(_ value: CodexStatisticsID) {
            withUnsafeBytes(of: value.first.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: value.second.littleEndian) { data.append(contentsOf: $0) }
        }
        mutating func optionalID(_ value: CodexStatisticsID?) { bool(value != nil); if let value { id(value) } }
        mutating func ids(_ values: Set<CodexStatisticsID>) {
            uint(UInt64(values.count))
            for value in values { id(value) }
        }
        mutating func usage(_ value: CodexTokenUsage) {
            uint(UInt64(value.input)); uint(UInt64(value.cached)); uint(UInt64(value.written)); uint(UInt64(value.output))
        }
        mutating func buckets(_ values: [CodexStatisticsBucket: TokenCount]) {
            uint(UInt64(values.count))
            for (bucket, tokens) in values {
                int(bucket.day); uint(UInt64(bucket.model))
                uint(UInt64(tokens.input)); uint(UInt64(tokens.output)); uint(UInt64(tokens.cacheRead)); uint(UInt64(tokens.cacheWrite))
            }
        }
        mutating func checkpoint(_ value: CodexStatisticsCheckpoint) {
            int(Int64(value.stamp.device)); uint(value.stamp.inode); uint(value.stamp.size)
            int(Int64(value.stamp.modifiedSeconds)); uint(UInt64(value.stamp.modifiedNanoseconds))
            uint(value.offset); optionalID(value.anchor); optionalID(value.prefix)
            id(value.thread); optionalID(value.session); bool(value.forked)
            bool(value.historyStart != nil); if let ordinal = value.historyStart { int(ordinal) }
            uint(UInt64(value.model)); id(value.turn); uint(UInt64(value.contextSequence)); bool(value.explicitTurn)
            uint(UInt64(value.models.count))
            for (turn, model) in value.models { id(turn); uint(UInt64(model)) }
            usage(value.cumulative); usage(value.inherited); bool(value.forkBaselineSet)
            ids(value.ledgerTurns); ids(value.responses); buckets(value.ledger)
            uint(UInt64(value.legacy.count))
            for (turn, totals) in value.legacy { id(turn); buckets(totals) }
        }
    }

    struct Reader {
        let data: Data
        var offset = 0
        var modelCount = 0

        mutating func uint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard offset < data.count else { throw Invalid.data }
                let byte = data[offset]; offset += 1
                if shift == 63 && byte > 1 { throw Invalid.data }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            throw Invalid.data
        }
        mutating func int() throws -> Int64 {
            let value = try uint()
            return Int64(bitPattern: value >> 1) ^ -Int64(value & 1)
        }
        mutating func count(minimumBytes: Int = 1) throws -> Int {
            let value = try uint()
            guard value <= UInt64((data.count - offset) / minimumBytes) else { throw Invalid.data }
            return Int(value)
        }
        mutating func number() throws -> Int {
            let value = try uint()
            guard value <= UInt64(Int.max / 16) else { throw Invalid.data }
            return Int(value)
        }
        mutating func bool() throws -> Bool {
            let value = try uint()
            guard value <= 1 else { throw Invalid.data }
            return value == 1
        }
        mutating func string() throws -> String {
            let length = try count()
            let end = offset + length
            defer { offset = end }
            guard let value = String(data: data[offset..<end], encoding: .utf8) else { throw Invalid.data }
            return value
        }
        mutating func id() throws -> CodexStatisticsID {
            guard data.count - offset >= 16 else { throw Invalid.data }
            defer { offset += 16 }
            return data.withUnsafeBytes {
                CodexStatisticsID(first: UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)), second: UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self)))
            }
        }
        mutating func optionalID() throws -> CodexStatisticsID? { try bool() ? id() : nil }
        mutating func ids() throws -> Set<CodexStatisticsID> {
            let count = try count(minimumBytes: 16)
            var values = Set<CodexStatisticsID>(minimumCapacity: count)
            for _ in 0..<count { values.insert(try id()) }
            return values
        }
        mutating func model() throws -> UInt32 {
            let value = try uint()
            guard value < modelCount else { throw Invalid.data }
            return UInt32(value)
        }
        mutating func usage() throws -> CodexTokenUsage {
            var usage = CodexTokenUsage()
            usage.input = try number(); usage.cached = try number(); usage.written = try number(); usage.output = try number()
            return usage
        }
        mutating func buckets() throws -> [CodexStatisticsBucket: TokenCount] {
            let count = try count(minimumBytes: 6)
            var values: [CodexStatisticsBucket: TokenCount] = [:]
            values.reserveCapacity(count)
            for _ in 0..<count {
                let key = try CodexStatisticsBucket(day: int(), model: model())
                values[key] = try TokenCount(input: number(), output: number(), cacheRead: number(), cacheWrite: number())
            }
            return values
        }
        mutating func checkpoint() throws -> CodexStatisticsCheckpoint {
            let device = try int()
            guard let device = Int32(exactly: device) else { throw Invalid.data }
            let inode = try uint(); let size = try uint(); let seconds = try int(); let nanos = try number()
            guard let seconds = Int(exactly: seconds), nanos < 1_000_000_000 else { throw Invalid.data }
            var value = CodexStatisticsCheckpoint(stamp: CodexFileStamp(device: device, inode: inode, size: size, modifiedSeconds: seconds, modifiedNanoseconds: nanos))
            value.offset = try uint(); value.anchor = try optionalID(); value.prefix = try optionalID()
            value.thread = try id(); value.session = try optionalID(); value.forked = try bool()
            if try bool() { value.historyStart = try int() }
            value.model = try model(); value.turn = try id(); value.contextSequence = try number(); value.explicitTurn = try bool()
            let contexts = try count(minimumBytes: 17)
            for _ in 0..<contexts { let key = try id(); value.models[key] = try model() }
            value.cumulative = try usage(); value.inherited = try usage(); value.forkBaselineSet = try bool()
            value.ledgerTurns = try ids(); value.responses = try ids(); value.ledger = try buckets()
            let turns = try count(minimumBytes: 17)
            for _ in 0..<turns { let key = try id(); value.legacy[key] = try buckets() }
            guard value.offset <= size else { throw Invalid.data }
            return value
        }
    }
}
