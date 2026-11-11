import AgentBarCore
@testable import ClaudeProvider
import Foundation
import Testing

struct UsageTests {
    @Test func fullResponseKeepsInactiveWindowsAndDeduplicatesLegacyFields() throws {
        let data = Data("""
        {"five_hour":{"utilization":8,"resets_at":"2026-11-11T05:00:00.123456+00:00"},
         "seven_day":{"utilization":32,"resets_at":"2026-11-16T00:00:00Z"},
         "seven_day_opus":{"utilization":13},"seven_day_sonnet":null,"seven_day_oauth_apps":null,
         "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null},
         "limits":[null,{"kind":"weekly_all","group":"weekly","percent":35,"is_active":false,"scope":null},
          {"kind":"weekly_scoped","group":"weekly","percent":41,"is_active":false,
           "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}},
          {"kind":"weekly_scoped","group":"weekly","percent":18,
           "scope":{"model":{"id":"claude-opus-4-6","display_name":"Opus"}}},
          {"kind":"weekly_scoped","group":"weekly","percent":99,
           "scope":{"model":{"id":"all-models","display_name":"All models"}}},
          {"kind":"unknown","percent":90},{"kind":"weekly_scoped","percent":"bad"}],
         "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"enabled":false},
         "member_dashboard_available":true,
         "seven_day_breakdown":{"rows":[{"key":"claude_code","display_name":"Claude Code","percent":100}]},
         "weekly_scoped_shares":[{"limit_index":1,"used_percent_of_weekly":20,"allowance_percent_of_weekly":50}]}
        """.utf8)
        let response = try JSONDecoder().decode(UsagePayload.self, from: data)
        #expect(response.windows.map(\.id) == ["session", "weekly", "weekly.fable", "weekly.opus"])
        #expect(response.windows.map(\.title) == ["5h", "Week", "Fable", "Opus"])
        #expect(response.windows.map(\.usedPercent) == [8, 35, 41, 18])
        #expect(response.windows.first?.resetsAt != nil)
    }

    @Test func absentAndMalformedWindowsRemainAbsent() throws {
        for body in ["{}", "{\"five_hour\":null,\"seven_day\":null}", "{\"seven_day\":{\"utilization\":null},\"five_hour\":{}}"] {
            #expect(try JSONDecoder().decode(UsagePayload.self, from: Data(body.utf8)).windows.isEmpty)
        }
        let response = try JSONDecoder().decode(UsagePayload.self, from: Data("{\"five_hour\":null,\"seven_day\":{\"utilization\":101}}".utf8))
        #expect(response.windows.map(\.id) == ["weekly"])
        #expect(response.windows.first?.usedPercent == 100)
    }

    @Test func missingAndExpiredCredentialsNeverCallNetwork() async throws {
        let space = try TestSpace()
        let account = try space.account()
        for (credential, expected) in [(nil, UsageError.signedOut), (testCredential(expired: true), .sessionExpired)] {
            let transport = TestTransport()
            let service = service(space, credentials: TestCredentials([credential]), transport: transport)
            await expectError(expected, service: service, account: account)
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test func unauthorizedRereadsAndOnlyRetriesChangedUnexpiredToken() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let original = testCredential("synthetic-original")
        for replacement in [original, testCredential("synthetic-expired", expired: true), nil] {
            let credentials = TestCredentials([original, replacement])
            let transport = TestTransport([testResponse(status: 401)])
            await expectError(.sessionExpired, service: service(space, credentials: credentials, transport: transport), account: account)
            #expect(await credentials.calls == 2)
            #expect(await transport.requests.count == 1)
        }
        let credentials = TestCredentials([original, testCredential("synthetic-rotated")])
        let transport = TestTransport([testResponse(status: 401), testResponse()])
        let snapshot = try await service(space, credentials: credentials, transport: transport).usage(for: account)
        #expect(snapshot.windows.first?.usedPercent == 37)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-rotated")
        #expect(requests.last?.url?.path == "/api/oauth/usage")
        let rejectedAgain = TestTransport([testResponse(status: 401), testResponse(status: 401)])
        await expectError(.sessionExpired, service: service(space,
            credentials: TestCredentials([original, testCredential("synthetic-other")]), transport: rejectedAgain), account: account)
        #expect(await rejectedAgain.requests.count == 2)
    }

    @Test func rateLimitsHTTPFailuresAndInvalidResponses() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let future = formatter.string(from: testNow.addingTimeInterval(90))
        let cases: [(UsageResponse, UsageError)] = [
            (testResponse(status: 429, headers: ["Retry-After": "120"]), .rateLimited(retryAfter: 120)),
            (testResponse(status: 429, headers: ["retry-after": future]), .rateLimited(retryAfter: 90)),
            (testResponse(status: 429), .rateLimited(retryAfter: nil)),
            (testResponse(status: 429, headers: ["Retry-After": "invalid"]), .rateLimited(retryAfter: nil)),
            (testResponse(status: 503), .unavailable("HTTP 503")),
            (testResponse(body: "invalid-json"), .unavailable("Invalid usage response"))
        ]
        for (response, error) in cases {
            await expectError(error, service: service(space, transport: TestTransport([response])), account: account)
        }
        await expectError(.unavailable("Network request failed"), service: service(space, transport: TestTransport(fail: true)), account: account)
        #expect(UsageService.retryAfter("-3", now: testNow) == 0)
    }

    @Test func cacheChoosesNewerTimestampAndChecksIdentity() async throws {
        let space = try TestSpace()
        let account = try space.account()
        try space.identity(account, cachedAt: testNow.addingTimeInterval(-60))
        let credentials = TestCredentials([testCredential()])
        let service = service(space, credentials: credentials)
        #expect(await service.cachedUsage(for: account)?.capturedAt == testNow.addingTimeInterval(-60))
        #expect(await credentials.calls == 0)
        _ = try await service.usage(for: account)
        #expect(await service.cachedUsage(for: account)?.capturedAt == testNow)
        let restored = self.service(space)
        #expect(await restored.cachedUsage(for: account)?.windows.first?.usedPercent == 37)
        try space.identity(account, cachedAt: testNow.addingTimeInterval(60), percent: 49)
        #expect(await service.cachedUsage(for: account)?.windows.first?.usedPercent == 49)
        try space.identity(account, cachedAt: testNow.addingTimeInterval(120), cachedUUID: "synthetic-other-account")
        #expect(await service.cachedUsage(for: account)?.windows.first?.usedPercent == 37)
        try space.identity(account, uuid: "synthetic-switched-account")
        #expect(await service.cachedUsage(for: account) == nil)
        let cacheFiles = try FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil)
        for file in cacheFiles {
            #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("synthetic-access"))
        }
    }

    @Test func everyUsageCallReadsCredentialsAgain() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let credentials = TestCredentials([testCredential(), nil])
        let transport = TestTransport()
        let service = service(space, credentials: credentials, transport: transport)
        _ = try await service.usage(for: account)
        await expectError(.signedOut, service: service, account: account)
        #expect(await credentials.calls == 2)
        #expect(await transport.requests.count == 1)
    }

    @Test func unidentifiedLoginsNeverPersistOrReuseUsage() async throws {
        for identity in [nil, ["emailAddress": "reader@example.invalid"], ["accountUuid": ""], ["accountUuid": "  "]] {
            let space = try TestSpace()
            let account = try space.account()
            if let identity {
                try space.write(["oauthAccount": identity, "cachedUsageUtilization": [
                    "accountUuid": identity["accountUuid"] ?? "", "fetchedAtMs": testNow.timeIntervalSince1970 * 1_000,
                    "utilization": ["seven_day": ["utilization": 99]]]], to: space.root.appendingPathComponent(".claude.json"))
            }
            let cache = DiskCache(directory: space.cache)
            let key = "claude.usage.v1." + account.home.standardizedFileURL.path + ":unknown"
            let old = UsageSnapshot(windows: [], capturedAt: testNow.addingTimeInterval(-60))
            try cache.save(old, key: key)
            let service = service(space, credentials: TestCredentials([testCredential("synthetic-first"), testCredential("synthetic-second")]),
                transport: TestTransport([testResponse(), testResponse(body: "{\"seven_day\":{\"utilization\":12}}")]))
            #expect(await service.cachedUsage(for: account) == nil)
            #expect(try await service.usage(for: account).windows.first?.usedPercent == 37)
            #expect(await service.cachedUsage(for: account) == nil)
            #expect(try await service.usage(for: account).windows.first?.usedPercent == 12)
            #expect(await service.cachedUsage(for: account) == nil)
            #expect(await self.service(space).cachedUsage(for: account) == nil)
            #expect(cache.load(UsageSnapshot.self, key: key) == old)
            #expect(try FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil).count == 1)
        }
    }

    private func service(_ space: TestSpace, credentials: any CredentialReading = TestCredentials([testCredential()]),
                         transport: any UsageTransporting = TestTransport()) -> UsageService {
        UsageService(credentials: credentials, transport: transport, clock: { testNow }, cache: DiskCache(directory: space.cache))
    }

    private func expectError(_ expected: UsageError, service: UsageService, account: Account) async {
        do { _ = try await service.usage(for: account); Issue.record("Expected a usage error") }
        catch { #expect(error == expected) }
    }
}
