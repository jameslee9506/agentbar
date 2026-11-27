import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexUsageTests {
    @Test func additionalLimitCannotMakeAnOlderMainWindowLookFresh() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        _ = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.quota(10),
            fixture.row("event_msg", ["type": "token_count", "rate_limits": [
                "limit_id": "extra", "limit_name": "Extra model",
                "primary": ["used_percent": 5, "window_minutes": 60],
            ]], at: CodexFixture.date.addingTimeInterval(20)),
        ])
        let cache = DiskCache(directory: fixture.cache)
        let service = CodexUsageService(transport: FakeCodexTransport(), renewal: FakeCodexRenewal(), clock: { CodexFixture.date.addingTimeInterval(30) }, cache: cache, rollouts: CodexRolloutUsage(), processes: FakeCodexProcesses())
        let credential = try #require(CodexCredential.read(home: home))
        let disk = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "Week", usedPercent: 70)], capturedAt: CodexFixture.date.addingTimeInterval(10))
        try cache.save(disk, key: await service.cacheKey(home: home, identity: credential.identity))
        #expect(await service.cachedUsage(for: fixture.account(home)) == disk)
    }

    @Test func windowsFollowDurationsAndTolerateNulls() throws {
        let fixture = try CodexFixture()
        let data = try fixture.json([
            "rate_limit": ["primary_window": ["used_percent": 130, "limit_window_seconds": 604800], "secondary_window": ["used_percent": 12.5, "limit_window_seconds": 18000, "reset_after_seconds": 50]],
            "additional_rate_limits": [
                ["limit_name": "Model Example", "metered_feature": "example", "rate_limit": ["primary_window": ["used_percent": 8, "limit_window_seconds": 3600], "secondary_window": NSNull()]],
                ["limit_name": "Missing", "rate_limit": NSNull()],
            ],
        ])
        let snapshot = try #require(CodexUsageDecoder.response(data, at: CodexFixture.date))
        #expect(snapshot.windows.map(\.title) == ["5h", "Week", "Model Example"])
        #expect(snapshot.windows.map(\.id) == ["session", "weekly", "additional.example.window.3600"])
        #expect(snapshot.windows.map(\.usedPercent) == [12.5, 100, 8])
        #expect(snapshot.windows.first?.resetsAt == CodexFixture.date.addingTimeInterval(50))
        let primaryOnly = try fixture.json(["rate_limit": ["primary_window": ["used_percent": 20, "limit_window_seconds": 604800], "secondary_window": NSNull()], "additional_rate_limits": NSNull()])
        #expect(CodexUsageDecoder.response(primaryOnly, at: CodexFixture.date)?.windows.map(\.title) == ["Week"])
        let malformed = try fixture.json(["rate_limit": ["primary_window": NSNull(), "secondary_window": ["used_percent": "invalid"]]])
        #expect(CodexUsageDecoder.response(malformed, at: CodexFixture.date)?.windows.isEmpty == true)
        let extremes = Data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":3,\"limit_window_seconds\":1e300,\"reset_at\":1e300}}}".utf8)
        #expect(CodexUsageDecoder.response(extremes, at: CodexFixture.date)?.windows.first?.resetsAt == nil)
    }

    @Test func liveRequestIgnoresIDTokenExpiryAndRereadsAuth() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let transport = FakeCodexTransport()
        let provider = fixture.provider(transport: transport)
        let account = fixture.account(home)
        let snapshot = try await provider.usage(for: account)
        #expect(snapshot.windows.first?.usedPercent == 25)
        #expect(await transport.requestValid)
        try FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
        await #expect(throws: UsageError.signedOut) { try await provider.usage(for: account) }
        #expect(await transport.calls == 1)
    }

    @Test func unrenewedExpiryAvoidsNetworkAndIsNotRetriedAtOnce() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home, expiry: CodexFixture.date)
        let transport = FakeCodexTransport()
        let renewal = FakeCodexRenewal()
        let provider = fixture.provider(transport: transport, renewal: renewal)
        for _ in 0..<2 {
            await #expect(throws: UsageError.sessionExpired) { try await provider.usage(for: fixture.account(home)) }
        }
        #expect(await transport.calls == 0)
        #expect(await renewal.calls == 1)
    }

    @Test func expiredLoginIsRenewedByTheCLI() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home, expiry: CodexFixture.date)
        let stale = try #require(CodexCredential.read(home: home))
        let transport = FakeCodexTransport()
        let renewal = FakeCodexRenewal { try? fixture.auth($0) }
        let snapshot = try await fixture.provider(transport: transport, renewal: renewal).usage(for: fixture.account(home))
        #expect(snapshot.windows.first?.usedPercent == 25)
        #expect(await renewal.calls == 1)
        let renewed = try #require(CodexCredential.read(home: home))
        #expect(renewed.accessToken != stale.accessToken)
        #expect(await transport.tokens == ["Bearer " + renewed.accessToken])
    }

    @Test func unauthorizedLoginIsRenewedOnce() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let transport = FakeCodexTransport(first: [401])
        let renewal = FakeCodexRenewal { try? fixture.auth($0, expiry: CodexFixture.date.addingTimeInterval(172_800)) }
        let snapshot = try await fixture.provider(transport: transport, renewal: renewal).usage(for: fixture.account(home))
        #expect(snapshot.windows.first?.usedPercent == 25)
        #expect(await renewal.calls == 1)
        #expect(Set(await transport.tokens).count == 2)

        let refused = FakeCodexTransport(status: 401)
        let again = FakeCodexRenewal { try? fixture.auth($0, expiry: CodexFixture.date.addingTimeInterval(259_200)) }
        await #expect(throws: UsageError.sessionExpired) {
            try await fixture.provider(transport: refused, renewal: again).usage(for: fixture.account(home))
        }
        #expect(await refused.calls == 2)
        #expect(await again.calls == 1)
    }

    @Test func renewalAsksTheAppServerOfTheHome() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let cli = try fixture.executable("""
        #!/bin/sh
        printf '%s' "$*" > "$CODEX_HOME/arguments"
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$CODEX_HOME/requests"
          case "$line" in
            *'"id":1'*) printf '{"id":1,"result":{}}\n' ;;
            *'"id":2'*) printf '{"method":"account/updated","params":{}}\n{"id":2,"result":{}}\n' ;;
          esac
        done
        """)
        await CodexLoginRenewal(executable: cli, timeout: .seconds(20)).renew(home: home)
        #expect(try String(contentsOf: home.appendingPathComponent("arguments"), encoding: .utf8) == "app-server")
        let requests = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(requests.map { $0?["method"] as? String } == ["initialize", "initialized", "account/read"])
        #expect((requests.last??["params"] as? [String: Any])?["refreshToken"] as? Bool == true)
    }

    @Test func renewalGivesUpOnASilentAppServer() async throws {
        let fixture = try CodexFixture()
        let cli = try fixture.executable("#!/bin/sh\nexec sleep 30\n")
        let started = Date()
        await CodexLoginRenewal(executable: cli, timeout: .milliseconds(200)).renew(home: try fixture.home())
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test(arguments: [401, 403, 429, 500])
    func httpErrorsAreMapped(_ status: Int) async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let transport = FakeCodexTransport(status: status, headers: ["Retry-After": "17.5"])
        let expected: UsageError = status == 401 ? .sessionExpired : status == 429 ? .rateLimited(retryAfter: 17.5) : .unavailable("HTTP \(status)")
        await #expect(throws: expected) { try await fixture.provider(transport: transport).usage(for: fixture.account(home)) }
    }

    @Test func retryAfterHTTPDateAndUnavailableResponses() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let transport = FakeCodexTransport(status: 429, headers: ["Retry-After": formatter.string(from: CodexFixture.date.addingTimeInterval(120))])
        await #expect(throws: UsageError.rateLimited(retryAfter: 120)) { try await fixture.provider(transport: transport).usage(for: fixture.account(home)) }
        await #expect(throws: UsageError.unavailable("Invalid usage response")) {
            try await fixture.provider(transport: FakeCodexTransport(body: "{}")).usage(for: fixture.account(home))
        }
        await #expect(throws: UsageError.unavailable("Network error")) {
            try await fixture.provider(transport: FakeCodexTransport(fails: true)).usage(for: fixture.account(home))
        }
    }

    @Test func cacheChoosesNewerSourceAndRejectsAnotherCreator() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let account = fixture.account(home)
        let rollouts = CodexRolloutUsage()
        let cache = DiskCache(directory: fixture.cache)
        let service = CodexUsageService(transport: FakeCodexTransport(), renewal: FakeCodexRenewal(), clock: { CodexFixture.date }, cache: cache, rollouts: rollouts, processes: FakeCodexProcesses())
        let credential = try #require(CodexCredential.read(home: home))
        let key = await service.cacheKey(home: home, identity: credential.identity)
        let disk = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "Week", usedPercent: 20)], capturedAt: CodexFixture.date.addingTimeInterval(-10))
        try cache.save(disk, key: key)
        #expect(await service.cachedUsage(for: account) == disk)
        let metadata = try #require(Data(fixture.metadata().utf8).withUnsafeBytes { CodexRecord.decode($0).flatMap(CodexThreadMetadata.init) })
        let row = try #require(Data(fixture.quota(30).utf8).withUnsafeBytes(CodexRecord.decode))
        rollouts.observe(row, metadata: metadata, home: home)
        #expect(await service.cachedUsage(for: account)?.windows.first?.usedPercent == 30)
        let wrongMetadata = try #require(Data(fixture.metadata("other", creator: "other-account").utf8).withUnsafeBytes { CodexRecord.decode($0).flatMap(CodexThreadMetadata.init) })
        let wrong = try #require(Data(fixture.quota(90, at: CodexFixture.date.addingTimeInterval(30)).utf8).withUnsafeBytes(CodexRecord.decode))
        rollouts.observe(wrong, metadata: wrongMetadata, home: home)
        #expect(await service.cachedUsage(for: account)?.windows.first?.usedPercent == 30)
        let live = try await service.usage(for: account)
        #expect(live.capturedAt == CodexFixture.date)
        try fixture.auth(home, accountID: "changed-account", accessAccount: "changed-account")
        #expect(await service.cachedUsage(for: account) == nil)
        let encoded = try Data(contentsOf: FileManager.default.contentsOfDirectory(at: fixture.cache, includingPropertiesForKeys: nil)[0])
        #expect(!String(decoding: encoded, as: UTF8.self).contains("access_token"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("refresh_token"))
    }

    @Test func recentDateDirectoriesSupplyOfflineUsageAndNewerDiskWins() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        _ = try fixture.rollout(home, lines: [fixture.metadata(), fixture.quota(31)])
        let account = fixture.account(home)
        #expect(await fixture.provider().cachedUsage(for: account)?.windows.first?.usedPercent == 31)
        let rollouts = CodexRolloutUsage()
        let cache = DiskCache(directory: fixture.cache)
        let service = CodexUsageService(transport: FakeCodexTransport(), renewal: FakeCodexRenewal(), clock: { CodexFixture.date.addingTimeInterval(20) }, cache: cache, rollouts: rollouts, processes: FakeCodexProcesses())
        let credential = try #require(CodexCredential.read(home: home))
        let key = await service.cacheKey(home: home, identity: credential.identity)
        let later = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "Week", usedPercent: 45)], capturedAt: CodexFixture.date.addingTimeInterval(10))
        try cache.save(later, key: key)
        #expect(await service.cachedUsage(for: account) == later)
    }
}
