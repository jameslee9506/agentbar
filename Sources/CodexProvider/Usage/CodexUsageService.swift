import AgentBarCore
import Foundation

actor CodexUsageService {
    private let transport: any CodexUsageTransport
    private let clock: @Sendable () -> Date
    private let cache: DiskCache
    private let rollouts: CodexRolloutUsage
    private let processes: any ProcessListing
    private var successful: [String: UsageSnapshot] = [:]
    private var offlineChecked: [String: Date] = [:]
    private var inspections: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    init(transport: any CodexUsageTransport, clock: @escaping @Sendable () -> Date, cache: DiskCache, rollouts: CodexRolloutUsage, processes: any ProcessListing) {
        self.transport = transport
        self.clock = clock
        self.cache = cache
        self.rollouts = rollouts
        self.processes = processes
    }

    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        guard let credential = CodexCredential.read(home: account.home) else { throw .signedOut }
        let now = clock()
        if let expiry = credential.expiresAt, expiry <= now { throw .sessionExpired }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/0.1", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch { throw .unavailable("Network error") }
        switch response.statusCode {
        case 200..<300: break
        case 401: throw .sessionExpired
        case 429: throw .rateLimited(retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: clock()))
        default: throw .unavailable("HTTP \(response.statusCode)")
        }
        guard let snapshot = CodexUsageDecoder.response(data, at: clock()) else { throw .unavailable("Invalid usage response") }
        let key = cacheKey(home: account.home, identity: credential.identity)
        successful[key] = snapshot
        try? cache.save(snapshot, key: key)
        return snapshot
    }

    func cachedUsage(for account: Account) async -> UsageSnapshot? {
        guard CodexCredential.read(home: account.home) != nil else { return nil }
        let home = account.home
        let homeKey = home.standardizedFileURL.path
        let now = clock()
        if inspections[homeKey] == nil, offlineChecked[homeKey].map({ now.timeIntervalSince($0) >= 2 }) ?? true {
            offlineChecked[homeKey] = now
            let rollouts = rollouts, processes = processes
            inspections[homeKey] = (UUID(), Task.detached(priority: .utility) {
                rollouts.inspectRecent(home: home, processes: processes)
            })
        }
        if let inspection = inspections[homeKey] {
            await inspection.task.value
            if inspections[homeKey]?.id == inspection.id { inspections.removeValue(forKey: homeKey) }
        }
        guard let credential = CodexCredential.read(home: home) else { return nil }
        let key = cacheKey(home: home, identity: credential.identity)
        if successful[key] == nil { successful[key] = cache.load(UsageSnapshot.self, key: key) }
        let offline = rollouts.latest(home: account.home, credential: credential)
        return [successful[key], offline].compactMap { $0 }.max { $0.capturedAt < $1.capturedAt }
    }

    func cacheKey(home: URL, identity: String) -> String {
        "codex.usage.v1.\(home.standardizedFileURL.path).\(identity)"
    }

    private static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
