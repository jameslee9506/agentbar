import AgentBarCore
import CryptoKit
import Foundation

struct CodexStatisticsArchive: Sendable {
    static let format = "codex.statistics.3"
    var since: Date
    let calendarKey: String
    var models = CodexStatisticsModels()
    var files: [String: CodexStatisticsCheckpoint] = [:]

    // Keep the storage key stable so a format upgrade replaces the home's old file.
    static func key(home: URL) -> String { "codex.statistics.v2." + home.standardizedFileURL.path }
    static func calendarKey(_ calendar: Calendar) -> String { "\(calendar.identifier):\(calendar.timeZone.identifier)" }

    static func load(cache: DiskCache, home: URL, calendar: Calendar) -> Self? {
        autoreleasepool {
            guard let encoded = cache.load(Data.self, key: key(home: home)), encoded.count >= 32 else { return nil }
            let body = Data(encoded.dropLast(32))
            guard Data(SHA256.hash(data: body)) == encoded.suffix(32) else { return nil }
            var reader = CodexStatisticsBinary.Reader(data: body)
            do {
                guard try reader.string() == format else { return nil }
                let storedCalendar = try reader.string()
                guard storedCalendar == calendarKey(calendar) else { return nil }
                var archive = Self(since: Date(timeIntervalSince1970: Double(try reader.int())), calendarKey: storedCalendar)
                let modelCount = try reader.count()
                guard modelCount > 0, modelCount <= 65536 else { return nil }
                var names: [String] = []
                for _ in 0..<modelCount { names.append(try reader.string()) }
                guard names.first == "unknown" else { return nil }
                archive.models = CodexStatisticsModels(names)
                reader.modelCount = modelCount
                let fileCount = try reader.count(minimumBytes: 32)
                archive.files.reserveCapacity(fileCount)
                for _ in 0..<fileCount {
                    try autoreleasepool {
                        let path = try reader.string()
                        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw CodexStatisticsBinary.Invalid.data }
                        archive.files[path] = try reader.checkpoint()
                    }
                }
                guard reader.offset == body.count else { return nil }
                return archive
            } catch { return nil }
        }
    }

    func save(cache: DiskCache, home: URL) {
        autoreleasepool {
            var writer = CodexStatisticsBinary.Writer()
            writer.string(Self.format); writer.string(calendarKey); writer.int(Int64(since.timeIntervalSince1970))
            writer.uint(UInt64(models.names.count))
            for name in models.names { writer.string(name) }
            writer.uint(UInt64(files.count))
            for (path, checkpoint) in files { writer.string(path); writer.checkpoint(checkpoint) }
            let checksum = Data(SHA256.hash(data: writer.data))
            writer.data.append(checksum)
            try? cache.save(writer.data, key: Self.key(home: home))
        }
    }

}
