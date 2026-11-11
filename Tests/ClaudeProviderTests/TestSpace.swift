import AgentBarCore
@testable import ClaudeProvider
import Foundation

final class TestSpace: Sendable {
    let directory: URL
    let root: URL
    let cache: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AgentBarClaudeTests-" + UUID().uuidString, isDirectory: true)
        root = directory.appendingPathComponent("homes", isDirectory: true)
        cache = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func account(_ name: String = ".claude") throws -> Account {
        let home = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return Account(id: AccountID(provider: .claude, home: name),
                       name: name == ".claude" ? "claude" : String(name.dropFirst(8)), home: home)
    }

    func write(_ object: [String: Any], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
    }

    func identity(_ account: Account, uuid: String = "synthetic-account", plan: String? = nil,
                  cachedAt: Date? = nil, cachedUUID: String? = nil, percent: Double = 24) throws {
        var identity: [String: Any] = ["accountUuid": uuid, "emailAddress": "reader@example.invalid",
                                       "organizationRateLimitTier": "default_claude_max_20x"]
        identity["planDisplayName"] = plan
        var object: [String: Any] = ["oauthAccount": identity]
        if let cachedAt {
            object["cachedUsageUtilization"] = ["accountUuid": cachedUUID ?? uuid,
                "fetchedAtMs": cachedAt.timeIntervalSince1970 * 1_000,
                "utilization": ["seven_day": ["utilization": percent]]]
        }
        let file = account.id.home == ".claude" ? root.appendingPathComponent(".claude.json")
            : account.home.appendingPathComponent(".claude.json")
        try write(object, to: file)
    }
}

let testNow = Date(timeIntervalSince1970: 1_794_355_200) // 2026-11-11 00:00:00 UTC.

func testCredential(_ token: String = "synthetic-access", expired: Bool = false) -> OAuthCredential {
    OAuthCredential(accessToken: token, expiresAt: testNow.addingTimeInterval(expired ? -1 : 3_600).timeIntervalSince1970 * 1_000,
                    subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
}

actor TestCredentials: CredentialReading {
    private var values: [OAuthCredential?]
    private(set) var calls = 0

    init(_ values: [OAuthCredential?] = []) { self.values = values }

    func read(for home: URL) -> OAuthCredential? {
        calls += 1
        if values.count > 1 { return values.removeFirst() }
        return values.first ?? nil
    }
}

struct HomeCredentials: CredentialReading {
    let values: [String: OAuthCredential]
    func read(for home: URL) async -> OAuthCredential? { values[home.lastPathComponent] }
}

actor TestTransport: UsageTransporting {
    enum Failure: Error { case offline }
    private var responses: [UsageResponse]
    private let fail: Bool
    private(set) var requests: [URLRequest] = []

    init(_ responses: [UsageResponse] = [], fail: Bool = false) {
        self.responses = responses
        self.fail = fail
    }

    func send(_ request: URLRequest) throws -> UsageResponse {
        requests.append(request)
        if fail { throw Failure.offline }
        return responses.isEmpty ? testResponse() : responses.removeFirst()
    }
}

func testResponse(status: Int = 200, headers: [String: String] = [:], body: String = "{\"seven_day\":{\"utilization\":37}}") -> UsageResponse {
    UsageResponse(status: status, headers: headers, data: Data(body.utf8))
}

final class TestProcesses: ProcessListing, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ProcessSummary] = []
    private var records: [Int32: RunningProcess] = [:]
    private var summaryReads = 0

    var calls: Int { lock.withLock { summaryReads } }

    func set(_ summaries: [ProcessSummary], details: [RunningProcess] = []) {
        lock.withLock {
            entries = summaries
            records = Dictionary(uniqueKeysWithValues: details.map { ($0.pid, $0) })
        }
    }

    func summaries() -> [ProcessSummary] { lock.withLock { summaryReads += 1; return entries } }
    func details(for pid: Int32) -> RunningProcess? { lock.withLock { records[pid] } }
    func openFilePaths(of pid: Int32) -> [String] { [] }
    func isAlive(_ pid: Int32, startedAt: Date?) -> Bool {
        lock.withLock { entries.contains { $0.pid == pid && (startedAt == nil || $0.startTime == startedAt) } }
    }
}

func testProcess(_ pid: Int32, home: URL, start: Date = testNow, name: String = "claude") -> (ProcessSummary, RunningProcess) {
    (ProcessSummary(pid: pid, parentPID: 1, name: name, startTime: start),
     RunningProcess(pid: pid, parentPID: 1, executablePath: "/synthetic/bin/" + name, arguments: [name],
                    environment: ["CLAUDE_CONFIG_DIR": home.path], workingDirectory: "/synthetic/project", startTime: start))
}
