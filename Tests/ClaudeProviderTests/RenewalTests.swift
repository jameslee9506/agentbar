import AgentBarCore
@testable import ClaudeProvider
import Foundation
import Testing

struct RenewalTests {
    @Test func expiredLoginIsRenewedAndSavedWhereTheCLIKeepsIt() async throws {
        let scene = try await Scene()
        let transport = TestTransport([renewalResponse()])
        let snapshot = try await scene.service(transport).usage(for: scene.account)
        #expect(snapshot.windows.first?.usedPercent == 37)

        let requests = await transport.requests
        #expect(requests.map(\.url?.absoluteString) == ["https://platform.claude.com/v1/oauth/token", "https://api.anthropic.com/api/oauth/usage"])
        #expect(requests[0].httpMethod == "POST")
        let sent = try #require(requests[0].httpBody)
        let body = try JSONSerialization.jsonObject(with: sent) as? [String: String]
        #expect(body == ["grant_type": "refresh_token", "refresh_token": "synthetic-refresh",
                         "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e", "scope": "user:inference user:profile"])
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-renewed")

        let saved = try #require(await scene.stored())
        let login = try #require(saved["claudeAiOauth"] as? [String: Any])
        #expect(login["accessToken"] as? String == "synthetic-renewed")
        #expect(login["refreshToken"] as? String == "synthetic-next")
        #expect(login["expiresAt"] as? Double == (testNow.timeIntervalSince1970 + 28_800) * 1_000)
        #expect(login["refreshTokenExpiresAt"] as? Double == (testNow.timeIntervalSince1970 + 2_592_000) * 1_000)
        #expect(login["scopes"] as? [String] == ["user:inference", "user:profile", "user:mcp_servers"])
        #expect(login["subscriptionType"] as? String == "max")
        #expect((saved["mcpOAuth"] as? [String: String]) == ["server": "synthetic-other-secret"])
        #expect(scene.locks.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func fileLoginsAreRenewedInPlaceAndStayPrivate() async throws {
        let scene = try await Scene(inKeychain: false)
        let transport = TestTransport([renewalResponse("{\"access_token\":\"synthetic-renewed\",\"expires_in\":3600}")])
        _ = try await scene.service(transport).usage(for: scene.account)
        let file = scene.account.home.appendingPathComponent(".credentials.json")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let login = try #require(document?["claudeAiOauth"] as? [String: Any])
        #expect(login["accessToken"] as? String == "synthetic-renewed")
        #expect(login["refreshToken"] as? String == "synthetic-refresh")
        #expect(login["scopes"] as? [String] == ["user:inference", "user:profile"])
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scene.account.home.path) == [".credentials.json"])
        #expect(await scene.keychain.writes == 0)
    }

    @Test func refusedRefreshTokensAreNotSentAgain() async throws {
        let scene = try await Scene()
        let transport = TestTransport([testResponse(status: 400, body: "{\"error\":\"invalid_grant\"}")])
        let service = scene.service(transport)
        for _ in 0..<2 {
            await #expect(throws: UsageError.sessionExpired) { try await service.usage(for: scene.account) }
        }
        #expect(await transport.requests.count == 1)
        #expect(await scene.keychain.writes == 0)
    }

    @Test func failedRenewalsLeaveTheLoginAndAreTriedAgain() async throws {
        let scene = try await Scene()
        let responses = [testResponse(status: 500), testResponse(status: 400, body: "{\"error\":\"invalid_scope\"}"),
                         renewalResponse("{\"expires_in\":3600}"), renewalResponse()]
        let transport = TestTransport(responses)
        let service = scene.service(transport)
        for _ in 0..<3 {
            await #expect(throws: UsageError.unavailable("Sign-in renewal failed")) { try await service.usage(for: scene.account) }
        }
        #expect(await scene.keychain.writes == 0)
        await #expect(throws: UsageError.unavailable("Sign-in renewal failed")) {
            try await scene.service(TestTransport(fail: true)).usage(for: scene.account)
        }
        #expect(try await service.usage(for: scene.account).windows.first?.usedPercent == 37)
        #expect(await scene.keychain.writes == 1)
    }

    @Test func loginRenewedByTheCLIIsAdopted() async throws {
        let scene = try await Scene()
        await scene.keychain.script([loginDocument(), loginDocument(access: "synthetic-sibling", expired: false)])
        let transport = TestTransport()
        _ = try await scene.service(transport).usage(for: scene.account)
        let requests = await transport.requests
        #expect(requests.map(\.url?.path) == ["/api/oauth/usage"])
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-sibling")
        #expect(await scene.keychain.writes == 0)
    }

    @Test func newerSignInIsNotOverwritten() async throws {
        let scene = try await Scene()
        let newer = loginDocument(access: "synthetic-signed-in", refresh: "synthetic-other-refresh", expired: false)
        await scene.keychain.script([loginDocument(), loginDocument(), newer])
        let transport = TestTransport([renewalResponse()])
        _ = try await scene.service(transport).usage(for: scene.account)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-signed-in")
        #expect(await scene.keychain.writes == 0)
    }

    @Test func heldLocksDeferRenewalAndAbandonedLocksAreTaken() async throws {
        let scene = try await Scene()
        let manager = FileManager.default
        for held in scene.locks.map(\.path) {
            try manager.createDirectory(atPath: held, withIntermediateDirectories: false)
            let transport = TestTransport()
            await #expect(throws: UsageError.unavailable("Sign-in renewal failed")) {
                try await scene.service(transport).usage(for: scene.account)
            }
            #expect(await transport.requests.isEmpty)
            #expect(scene.locks.map { manager.fileExists(atPath: $0.path) } == scene.locks.map { $0.path == held })

            try manager.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: held)
            try await scene.reset()
            _ = try await scene.service(TestTransport([renewalResponse()])).usage(for: scene.account)
            #expect(scene.locks.allSatisfy { !manager.fileExists(atPath: $0.path) })
            try await scene.reset()
        }
    }

    @Test func unauthorizedUnexpiredLoginIsRenewedOnce() async throws {
        let scene = try await Scene(expired: false)
        let transport = TestTransport([testResponse(status: 401), renewalResponse()])
        _ = try await scene.service(transport).usage(for: scene.account)
        let requests = await transport.requests
        #expect(requests.map(\.url?.path) == ["/api/oauth/usage", "/v1/oauth/token", "/api/oauth/usage"])
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-renewed")

        try await scene.reset()
        let refused = TestTransport([testResponse(status: 401), renewalResponse(), testResponse(status: 401)])
        await #expect(throws: UsageError.sessionExpired) { try await scene.service(refused).usage(for: scene.account) }
        #expect(await refused.requests.count == 3)
    }

    @Test func renewalThatCouldNotBeSavedIsSavedBeforeAnythingElse() async throws {
        let scene = try await Scene()
        await scene.keychain.failWrites(3)
        let transport = TestTransport([renewalResponse()])
        let service = scene.service(transport)
        _ = try await service.usage(for: scene.account)
        #expect(await scene.keychain.writes == 0)
        _ = try await service.usage(for: scene.account)
        #expect(await scene.keychain.writes == 1)
        #expect(await transport.requests.map(\.url?.path) == ["/v1/oauth/token", "/api/oauth/usage", "/api/oauth/usage"])
        #expect((await scene.stored()?["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String == "synthetic-next")
    }

    @Test func concurrentReadsRenewOnce() async throws {
        let scene = try await Scene()
        let transport = TestTransport([renewalResponse()])
        let service = scene.service(transport)
        async let first = service.usage(for: scene.account)
        async let second = service.usage(for: scene.account)
        _ = try await (first, second)
        #expect(await transport.requests.filter { $0.url?.path == "/v1/oauth/token" }.count == 1)
        #expect(await scene.keychain.writes == 1)
    }
}

/// One account whose login sits in a Keychain in memory, or in its `.credentials.json`.
private struct Scene {
    let space: TestSpace
    let account: Account
    let keychain = TestKeychain()
    let store: CredentialStore
    private let inKeychain: Bool
    private let expired: Bool

    init(inKeychain: Bool = true, expired: Bool = true) async throws {
        space = try TestSpace()
        account = try space.account(".claude-work")
        self.inKeychain = inKeychain
        self.expired = expired
        let keychain = keychain
        store = CredentialStore(defaultHome: space.root.appendingPathComponent(".claude"),
                                readService: { await keychain.read($0) }, writeService: { await keychain.write($0, $1) })
        try await reset()
    }

    var service: String { CredentialStore.service(for: account.home, defaultHome: store.defaultHome) }

    var locks: [URL] {
        [account.home.appendingPathComponent(".oauth_refresh.lock"),
         URL(fileURLWithPath: account.home.resolvingSymlinksInPath().path + ".lock")]
    }

    /// Puts the original login back.
    func reset() async throws {
        let document = loginDocument(expired: expired)
        if inKeychain {
            await keychain.set(document, service: service)
        } else {
            try document.write(to: account.home.appendingPathComponent(".credentials.json"))
        }
    }

    func stored() async -> [String: Any]? {
        guard let document = await keychain.items[service] else { return nil }
        return (try? JSONSerialization.jsonObject(with: document)) as? [String: Any]
    }

    func service(_ transport: TestTransport) -> UsageService {
        let renewal = LoginRenewal(store: store, transport: transport, clock: { testNow }, lockWait: .milliseconds(1))
        return UsageService(credentials: store, renewal: renewal, transport: transport, clock: { testNow },
                            cache: DiskCache(directory: space.cache))
    }
}

private func loginDocument(access: String = "synthetic-access", refresh: String = "synthetic-refresh", expired: Bool = true) -> Data {
    let login: [String: Any] = [
        "accessToken": access, "refreshToken": refresh,
        "expiresAt": testNow.addingTimeInterval(expired ? -1 : 3_600).timeIntervalSince1970 * 1_000,
        "refreshTokenExpiresAt": 1, "scopes": ["user:inference", "user:profile"],
        "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x",
    ]
    return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": login, "mcpOAuth": ["server": "synthetic-other-secret"]])
}

private func renewalResponse(_ body: String = """
    {"access_token":"synthetic-renewed","refresh_token":"synthetic-next","expires_in":28800,
     "refresh_token_expires_in":2592000,"scope":"user:inference user:profile user:mcp_servers"}
    """) -> UsageResponse {
    testResponse(body: body)
}
