import AgentBarCore
import Foundation

struct TranscriptCache: Codable {
    static let currentVersion = 5
    private struct Manifest: Encodable {
        let version: Int
        let since: Date
        let calendar: Calendar
        let checkpoints: [TranscriptCheckpoint]
        let models: [String]
        let totals: UsageStatistics
    }
    let version: Int
    let since: Date
    let calendar: Calendar
    let checkpoints: [TranscriptCheckpoint]
    let models: [String]
    let totals: UsageStatistics
    let ledger: Data
    let checksum: TranscriptHash

    init(version: Int, since: Date, calendar: Calendar, checkpoints: [TranscriptCheckpoint],
         models: [String], totals: UsageStatistics, ledger: Data, checksum: TranscriptHash? = nil) {
        self.version = version
        self.since = since
        self.calendar = calendar
        self.checkpoints = checkpoints
        self.models = models
        self.totals = totals
        self.ledger = ledger
        self.checksum = checksum ?? Self.fingerprint(version: version, since: since, calendar: calendar,
            checkpoints: checkpoints, models: models, totals: totals, ledger: ledger) ?? TranscriptHash(low: 0, high: 0)
    }

    var isValid: Bool {
        version == Self.currentVersion && ledger.count >= 8
            && checksum == Self.fingerprint(version: version, since: since, calendar: calendar,
                checkpoints: checkpoints, models: models, totals: totals, ledger: ledger)
            && Set(models).count == models.count
            && Set(checkpoints.map(\.path)).count == checkpoints.count
            && checkpoints.allSatisfy { !$0.path.hasPrefix("/") && !$0.path.split(separator: "/").contains("..") }
    }

    static func key(home: URL) -> String { "claude.statistics." + home.path }

    private static func fingerprint(version: Int, since: Date, calendar: Calendar, checkpoints: [TranscriptCheckpoint],
                                    models: [String], totals: UsageStatistics, ledger: Data) -> TranscriptHash? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifest = Manifest(version: version, since: since, calendar: calendar,
                                checkpoints: checkpoints, models: models, totals: totals)
        guard let data = try? encoder.encode(manifest) else { return nil }
        return TranscriptHash.digest([data, ledger])
    }
}
