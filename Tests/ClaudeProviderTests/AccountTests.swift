import AgentBarCore
@testable import ClaudeProvider
import CryptoKit
import Foundation
import Testing

struct AccountTests {
    @Test func knownIdentityAndPlanAvoidRedundantCredentialReads() async throws {
        let space = try TestSpace()
        let standard = try space.account()
        let work = try space.account(".claude-work")
        try space.identity(standard, plan: "Ultra")
        try space.identity(work)
        let credentials = TestCredentials([testCredential()])
        let discovery = AccountDiscovery(root: space.root, credentials: credentials)
        #expect(await discovery.accounts().map(\.plan) == ["Ultra", "Max 20x"])
        #expect(await credentials.calls == 0)
        try space.write(["oauthAccount": ["accountUuid": "synthetic-account", "organizationType": "claude_pro"]],
                        to: work.home.appendingPathComponent(".claude.json"))
        #expect(await discovery.accounts().map(\.plan) == ["Ultra", "Max 20x"])
        #expect(await credentials.calls == 1)
    }

    @Test func discoversIdentityOrCredentialHomesWithoutMerging() async throws {
        let space = try TestSpace()
        let standard = try space.account()
        let work = try space.account(".claude-work")
        _ = try space.account(".claude-token")
        _ = try space.account(".claude-empty")
        _ = try space.account(".claude-playwright-profile")
        _ = try space.account("unrelated")
        try space.identity(standard, plan: "Ultra")
        try space.identity(work)
        try space.write(["oauthAccount": [:]], to: space.root.appendingPathComponent(".claude-empty/.claude.json"))
        try Data().write(to: space.root.appendingPathComponent(".claude-file"))
        let discovery = AccountDiscovery(root: space.root, credentials: HomeCredentials(values: [".claude-token": testCredential()]))
        let accounts = await discovery.accounts()
        #expect(accounts.map(\.name) == ["claude", "token", "work"])
        #expect(accounts.map(\.id.home) == [".claude", ".claude-token", ".claude-work"])
        #expect(accounts.map(\.plan) == ["Ultra", "Max 20x", "Max 20x"])
        #expect(accounts[0].email == "reader@example.invalid")
        #expect(accounts[1].email == nil)
        #expect(accounts[0].id != accounts[2].id)
    }

    @Test func serviceNamesNeverBorrowDefaultCredentials() async throws {
        let space = try TestSpace()
        let standard = try space.account()
        let work = try space.account(".claude-work")
        #expect(KeychainCredentialReader.service(for: standard.home, defaultHome: standard.home) == "Claude Code-credentials")
        let digest = SHA256.hash(data: Data(work.home.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let expected = "Claude Code-credentials-" + digest.prefix(8)
        #expect(KeychainCredentialReader.service(for: work.home, defaultHome: standard.home) == expected)
        let requested = ServiceRecorder()
        let reader = KeychainCredentialReader(defaultHome: standard.home, readService: { service in
            await requested.record(service)
            return nil
        })
        #expect(await reader.read(for: work.home) == nil)
        #expect(await requested.services == [expected])
        try space.write(["claudeAiOauth": ["accessToken": "synthetic-file-token", "refreshToken": "ignored-synthetic-value",
                                           "expiresAt": 1_900_000_000_000]], to: work.home.appendingPathComponent(".credentials.json"))
        let credential = await reader.read(for: work.home)
        #expect(credential?.accessToken == "synthetic-file-token")
        #expect(credential?.expiration == Date(timeIntervalSince1970: 1_900_000_000))
        let preferred = KeychainCredentialReader(defaultHome: standard.home, readService: { _ in
            Data("{\"claudeAiOauth\":{\"accessToken\":\"synthetic-keychain-token\"}}".utf8)
        })
        #expect(await preferred.read(for: work.home)?.accessToken == "synthetic-keychain-token")
    }

    @Test func planFallbacks() {
        #expect(AccountDiscovery.humanizedPlan("default_claude_max_20x") == "Max 20x")
        #expect(AccountDiscovery.humanizedPlan("pro") == "Pro")
        #expect(AccountDiscovery.humanizedPlan(nil) == nil)
    }
}

private actor ServiceRecorder {
    var services: [String] = []
    func record(_ service: String) { services.append(service) }
}
