import AgentBarCore
import Foundation

struct CodexStatisticsCheckpoint: Sendable {
    var stamp: CodexFileStamp
    var offset: UInt64 = 0
    var anchor: CodexStatisticsID?
    var prefix: CodexStatisticsID?
    var thread: CodexStatisticsID = .zero
    var session: CodexStatisticsID?
    var forked = false
    var historyStart: Int64?
    var model: UInt32 = 0
    var turn: CodexStatisticsID = .zero
    var contextSequence = 0
    var explicitTurn = false
    var models: [CodexStatisticsID: UInt32] = [:]
    var cumulative = CodexTokenUsage.zero
    var inherited = CodexTokenUsage.zero
    var forkBaselineSet = false
    var ledgerTurns: Set<CodexStatisticsID> = []
    var responses: Set<CodexStatisticsID> = []
    var ledger: [CodexStatisticsBucket: TokenCount] = [:]
    var legacy: [CodexStatisticsID: [CodexStatisticsBucket: TokenCount]] = [:]

    var totals: [CodexStatisticsBucket: TokenCount] {
        var totals = ledger
        for (turn, buckets) in legacy where !ledgerTurns.contains(turn) { totals.add(buckets) }
        return totals
    }

    mutating func identify(_ metadata: CodexThreadMetadata) {
        thread = CodexStatisticsID(metadata.id)
        session = metadata.sessionID.map(CodexStatisticsID.init)
        forked = metadata.forked
        historyStart = metadata.historyStart
        turn = thread.combined(with: "turn:opening")
    }

    func canAppend(file: URL, stamp: CodexFileStamp) -> Bool {
        guard self.stamp.device == stamp.device, self.stamp.inode == stamp.inode, stamp.size >= offset else { return false }
        if self.stamp == stamp { return true }
        guard stamp.size > self.stamp.size else { return false }
        return prefix == CodexStatisticsID.anchor(file, endingAt: min(self.stamp.size, 256))
            && anchor == CodexStatisticsID.anchor(file, endingAt: offset)
    }

    mutating func read(
        file: URL, home: URL, since: Date, calendar: Calendar, through limit: UInt64? = nil,
        names: inout CodexStatisticsModels, rollouts: CodexRolloutUsage,
        select: (CodexStatisticsCharge) -> TokenCount? = { $0.tokens }
    ) {
        autoreleasepool {
            guard let metadata = CodexRolloutFile.metadata(file) else { return }
            if offset == 0 { identify(metadata) }
            guard CodexStatisticsID(metadata.id) == thread else { return }
            guard let observed = CodexFileStamp(file) else { return }
            let end = min(observed.size, limit ?? .max)
            let completed = try? JSONLines.forEachLine(in: file, fromOffset: offset, upTo: end, maximumLineBytes: 2 * 1024 * 1024) { bytes in
                guard let record = CodexRecord.decode(bytes) else { return }
                consume(record, since: since, calendar: calendar, names: &names, select: select)
                rollouts.observe(record, metadata: metadata, home: home)
            }
            guard let completed else { return }
            offset = completed
            stamp = CodexFileStamp(device: observed.device, inode: observed.inode, size: end, modifiedSeconds: observed.modifiedSeconds, modifiedNanoseconds: observed.modifiedNanoseconds)
            anchor = CodexStatisticsID.anchor(file, endingAt: offset)
            prefix = CodexStatisticsID.anchor(file, endingAt: min(stamp.size, 256))
        }
    }

    mutating func prune(before day: Int64) {
        ledger = ledger.filter { $0.key.day >= day }
        for turn in Array(legacy.keys) {
            legacy[turn] = legacy[turn]?.filter { $0.key.day >= day }
            if legacy[turn]?.isEmpty == true { legacy.removeValue(forKey: turn) }
        }
    }

    private mutating func consume(
        _ record: CodexRecord, since: Date, calendar: Calendar,
        names: inout CodexStatisticsModels, select: (CodexStatisticsCharge) -> TokenCount?
    ) {
        if record.type == "session_meta" { return }
        if let historyStart, (record.ordinal ?? .min) < historyStart {
            if record.event == "token_count", let info = record.payload["info"] as? [String: Any],
               let total = CodexTokenUsage(info["total_token_usage"]) { inherited.retainHighWater(total) }
            return
        }
        if record.type == "turn_context" {
            if let id = record.payload["turn_id"] as? String { turn = turnID(id); explicitTurn = true }
            else if !explicitTurn { contextSequence += 1; turn = turnID("context-\(contextSequence)") }
            model = names.index(record.payload["model"] as? String ?? "unknown")
            models[turn] = model
            return
        }
        if record.event == "task_started", let id = record.payload["turn_id"] as? String { turn = turnID(id); explicitTurn = true }
        if record.event == "task_complete" || record.event == "turn_aborted" { explicitTurn = false }
        if record.type == "token_usage_record" { response(record, since: since, calendar: calendar, names: &names, select: select) }
        else if record.type == "event_msg", record.event == "token_count" { counter(record, since: since, calendar: calendar, select: select) }
    }

    private mutating func response(
        _ record: CodexRecord, since: Date, calendar: Calendar,
        names: inout CodexStatisticsModels, select: (CodexStatisticsCharge) -> TokenCount?
    ) {
        let payload = record.payload
        guard let id = payload["thread_id"] as? String, CodexStatisticsID(id) == thread,
              let response = payload["response_id"] as? String, !response.isEmpty,
              let usage = CodexTokenUsage(payload["usage"]), let timestamp = record.timestamp else { return }
        if let supplied = payload["session_id"] as? String, let session, CodexStatisticsID(supplied) != session { return }
        let currentTurn = (payload["turn_id"] as? String).map(turnID) ?? turn
        ledgerTurns.insert(currentTurn)
        legacy.removeValue(forKey: currentTurn)
        forkBaselineSet = true
        if let total = CodexTokenUsage(payload["thread_token_usage"]) { cumulative.retainHighWater(total) }
        let key = thread.combined(with: "response:" + response)
        guard responses.insert(key).inserted, timestamp >= since else { return }
        let model = models[currentTurn] ?? names.index(payload["model"] as? String ?? "unknown")
        let bucket = CodexStatisticsBucket(day: Int64(calendar.startOfDay(for: timestamp).timeIntervalSince1970), model: model)
        let charge = CodexStatisticsCharge(key: key, turn: currentTurn, ledger: true, bucket: bucket, tokens: usage.tokens)
        if let tokens = select(charge) { ledger[bucket, default: .zero] += tokens }
    }

    private mutating func counter(
        _ record: CodexRecord, since: Date, calendar: Calendar, select: (CodexStatisticsCharge) -> TokenCount?
    ) {
        guard let info = record.payload["info"] as? [String: Any],
              let total = CodexTokenUsage(info["total_token_usage"]), let timestamp = record.timestamp else { return }
        if forked && !forkBaselineSet {
            guard historyStart != nil else { return }
            let last = CodexTokenUsage(info["last_token_usage"])
            if inherited != .zero, total.delta(from: inherited) != nil { cumulative = inherited }
            else if last != total { cumulative = total }
            forkBaselineSet = true
        }
        let baseline = cumulative
        let delta = total.delta(from: baseline)
        cumulative.retainHighWater(total)
        guard let delta, delta.tokens != .zero, timestamp >= since, !ledgerTurns.contains(turn) else { return }
        let bucket = CodexStatisticsBucket(day: Int64(calendar.startOfDay(for: timestamp).timeIntervalSince1970), model: model)
        let charge = CodexStatisticsCharge(key: thread.combined(with: "legacy:" + total.key), turn: turn, ledger: false, bucket: bucket, tokens: delta.tokens, cumulative: total, baseline: baseline, timestamp: timestamp)
        if let tokens = select(charge), tokens != .zero { legacy[turn, default: [:]][bucket, default: .zero] += tokens }
    }

    private func turnID(_ value: String) -> CodexStatisticsID { thread.combined(with: "turn:" + value) }
}
