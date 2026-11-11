import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexAccountsTests {
    @Test func discoveryKeepsHomesSeparateAndSkipsUnsupportedCredentials() async throws {
        let fixture = try CodexFixture()
        try fixture.auth(fixture.home())
        try fixture.auth(fixture.home(".codex-work"), expiry: CodexFixture.date.addingTimeInterval(-1))
        _ = try fixture.home(".codex-empty")
        try fixture.auth(fixture.home(".codexSomething"))
        try fixture.auth(fixture.home(".codex-api"), mode: "apikey")
        try fixture.auth(fixture.home(".codex-unknown"), mode: "chatgptAuthTokens")
        let apiOnly = try fixture.home(".codex-key")
        try fixture.json(["OPENAI_API_KEY": "synthetic-key"]).write(to: apiOnly.appendingPathComponent("auth.json"))
        let accounts = await fixture.provider().accounts()
        #expect(accounts.map(\.name) == ["codex", "work"])
        #expect(accounts.map(\.id.home) == [".codex", ".codex-work"])
        #expect(accounts.allSatisfy { $0.plan == "Pro" && $0.email == "person@example.test" })
    }

    @Test func claimsFallbackAndMissingMode() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home, mode: nil, accountID: nil)
        let credential = try #require(CodexCredential.read(home: home))
        #expect(credential.accountID == "account-example")
        #expect(credential.email == "person@example.test")
        #expect(credential.plan == "Pro")
        #expect(credential.expiresAt == CodexFixture.date.addingTimeInterval(86400))
        let token = CodexFixture.jwt(["https://api.openai.com/auth": ["chatgpt_account_id": "fallback-example"], "https://api.openai.com/profile": ["email": "fallback@example.test"]])
        try fixture.json(["tokens": ["access_token": token]]).write(to: home.appendingPathComponent("auth.json"))
        let fallback = try #require(CodexCredential.read(home: home))
        #expect(fallback.accountID == "fallback-example")
        #expect(fallback.email == "fallback@example.test")
        #expect(fallback.expiresAt == nil)
    }

    @Test(arguments: ["", " ", "not-a-jwt"])
    func unusableTokensNeedAnAccount(_ access: String) throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.json(["tokens": ["access_token": access]]).write(to: home.appendingPathComponent("auth.json"))
        #expect(CodexCredential.read(home: home) == nil)
    }
}
