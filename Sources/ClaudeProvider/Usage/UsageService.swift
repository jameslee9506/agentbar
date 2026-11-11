import AgentBarCore
import Foundation

actor UsageService {
    private let credentials: any CredentialReading
    private let transport: any UsageTransporting
    private let clock: @Sendable () -> Date
    private let cache: DiskCache
    private var successful: [String: UsageSnapshot] = [:]

    init(credentials: any CredentialReading, transport: any UsageTransporting,
         clock: @escaping @Sendable () -> Date, cache: DiskCache) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.cache = cache
    }

    func cachedUsage(for account: Account) -> UsageSnapshot? {
        let document = IdentityDocument.read(home: account.home)
        guard let identity = verifiedIdentity(document) else { return nil }
        let key = cacheKey(account, identity: identity)
        let saved = successful[key] ?? cache.load(UsageSnapshot.self, key: key)
        guard let local = document?.cachedUsageUtilization,
              local.accountUuid == identity,
              local.fetchedAtMs.isFinite, local.fetchedAtMs > 0
        else { return saved }
        let snapshot = UsageSnapshot(windows: local.utilization.windows,
                                     capturedAt: Date(timeIntervalSince1970: local.fetchedAtMs / 1_000))
        return saved.map { $0.capturedAt >= snapshot.capturedAt ? $0 : snapshot } ?? snapshot
    }

    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        guard let credential = await credentials.read(for: account.home) else { throw .signedOut }
        guard !credential.isExpired(at: clock()) else { throw .sessionExpired }
        var identity = verifiedIdentity(IdentityDocument.read(home: account.home))
        var response = try await request(credential.accessToken)
        if response.status == 401 {
            guard let replacement = await credentials.read(for: account.home),
                  replacement.accessToken != credential.accessToken,
                  !replacement.isExpired(at: clock())
            else { throw .sessionExpired }
            identity = verifiedIdentity(IdentityDocument.read(home: account.home))
            response = try await request(replacement.accessToken)
        }
        switch response.status {
        case 200:
            guard let payload = try? JSONDecoder().decode(UsagePayload.self, from: response.data) else {
                throw .unavailable("Invalid usage response")
            }
            let snapshot = UsageSnapshot(windows: payload.windows, capturedAt: clock())
            if let identity, identity == verifiedIdentity(IdentityDocument.read(home: account.home)) {
                let key = cacheKey(account, identity: identity)
                if successful[key].map({ $0.capturedAt <= snapshot.capturedAt }) ?? true {
                    successful[key] = snapshot
                    try? cache.save(snapshot, key: key)
                }
            }
            return snapshot
        case 401: throw .sessionExpired
        case 429:
            let retry = response.headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
            throw .rateLimited(retryAfter: Self.retryAfter(retry, now: clock()))
        default: throw .unavailable("HTTP \(response.status)")
        }
    }

    private func request(_ token: String) async throws(UsageError) -> UsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AgentBar/1.0", forHTTPHeaderField: "User-Agent")
        do { return try await transport.send(request) }
        catch { throw .unavailable("Network request failed") }
    }

    private func verifiedIdentity(_ document: IdentityDocument?) -> String? {
        guard let identity = document?.oauthAccount?.accountUuid,
              !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return identity
    }

    private func cacheKey(_ account: Account, identity: String) -> String {
        "claude.usage.v1." + account.home.standardizedFileURL.path + ":" + identity
    }

    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let raw = value else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return max(0, date.timeIntervalSince(now)) }
        }
        return nil
    }
}
