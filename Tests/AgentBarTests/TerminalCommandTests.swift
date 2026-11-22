@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

struct TerminalCommandTests {
    @Test func wordsSelectProvidersAndNamesAndOptionsFollowAnywhere() throws {
        let plain = try TerminalCommand(arguments: ["--terminal"])
        #expect(plain.providers.isEmpty && plain.names.isEmpty)
        #expect(!plain.includesHidden && plain.allowsColors && !plain.demo && !plain.showsHelp)
        let command = try TerminalCommand(arguments: ["--terminal", "Claude", "Work", "--all", "side", "--no-color"])
        #expect(command.providers == [.claude])
        #expect(command.names == ["Work", "side"])
        #expect(command.includesHidden && !command.allowsColors)
        #expect(try TerminalCommand(arguments: ["--demo", "--terminal", "-a", "-h"]).demo)
        #expect(try TerminalCommand(arguments: ["--terminal", "--help"]).showsHelp)
        #expect(throws: TerminalCommand.UnknownOption(option: "--json")) {
            try TerminalCommand(arguments: ["--terminal", "--json"])
        }
        // The app's own options are none of the command's.
        #expect(throws: TerminalCommand.UnknownOption(option: "--log")) {
            try TerminalCommand(arguments: ["--terminal", "--log"])
        }
    }

    @Test func accountsMatchAProviderAndAnyOfTheNames() throws {
        let work = TestFixtures.account("work")
        let side = TestFixtures.account("side-project")
        let codex = TestFixtures.account("work", kind: .codex)
        func selected(_ words: String...) throws -> [AccountID] {
            let command = try TerminalCommand(arguments: ["--terminal"] + words)
            return [work, side, codex].filter(command.selects).map(\.id)
        }
        #expect(try selected() == [work.id, side.id, codex.id])
        #expect(try selected("codex") == [codex.id])
        #expect(try selected("claude", "codex") == [work.id, side.id, codex.id])
        #expect(try selected("WORK") == [work.id, codex.id])
        #expect(try selected("work", "SIDE") == [work.id, side.id, codex.id])
        #expect(try selected("claude", "wor") == [work.id])
        #expect(try selected("nothing").isEmpty)
    }
}

struct TerminalAccountsTests {
    private let now = TestFixtures.date

    @Test func recentUsageIsShownWithoutARequestAndOlderUsageIsReadAgain() async throws {
        let recent = TestFixtures.account("recent")
        let old = TestFixtures.account("old")
        let provider = TestProvider(kind: .claude, accounts: [recent, old])
        provider.setCache(TestFixtures.snapshot(11, at: now.addingTimeInterval(-59)), for: recent.id)
        provider.setResult(.success(TestFixtures.snapshot(99, at: now)), for: recent.id)
        provider.setCache(TestFixtures.snapshot(22, at: now.addingTimeInterval(-60)), for: old.id)
        provider.setResult(.success(TestFixtures.snapshot(33, at: now)), for: old.id)
        let states = await TerminalAccounts.load([recent, old], from: [provider], now: { TestFixtures.date })
        #expect(states.map(\.id) == [recent.id, old.id])
        #expect(states[0].usage?.windows.first?.usedPercent == 11)
        #expect(provider.calls(for: recent.id) == 0)
        #expect(states[1].usage?.windows.first?.usedPercent == 33)
        #expect(provider.calls(for: old.id) == 1)
        #expect(states.allSatisfy { !$0.isStale && $0.usageError == nil })
        #expect(states.allSatisfy { DisplayFormat.status($0, now: now) == nil })
    }

    @Test func usageThatCannotBeReadStaysAsLastKnownWithItsError() async throws {
        let limited = TestFixtures.account("limited")
        let signedOut = TestFixtures.account("signed-out", kind: .codex)
        let claude = TestProvider(kind: .claude, accounts: [limited])
        let codex = TestProvider(kind: .codex, accounts: [signedOut])
        claude.setCache(TestFixtures.snapshot(82, at: now.addingTimeInterval(-900)), for: limited.id)
        claude.setResult(.failure(.rateLimited(retryAfter: 30)), for: limited.id)
        codex.setStatistics(UsageStatistics(days: [DailyUsage(day: now, byModel: ["test-model": TokenCount(input: 12)])]), for: signedOut.id)
        // Shown in the order asked for, whichever provider answers first.
        let states = await TerminalAccounts.load([signedOut, limited], from: [claude, codex], now: { TestFixtures.date })
        #expect(states.map(\.id) == [signedOut.id, limited.id])
        #expect(states[0].usage == nil)
        #expect(states[0].usageError == .signedOut)
        #expect(states[0].statistics.total.input == 12)
        #expect(states[1].usage?.windows.first?.usedPercent == 82)
        #expect(states[1].usageError == .rateLimited(retryAfter: 30))
        #expect(DisplayFormat.status(states[1], now: now) == "Stale · Rate limited")
        #expect(await TerminalAccounts.discover([claude, codex]).map(\.id).sorted() == [limited.id, signedOut.id].sorted())
    }

    @Test func sessionsAreThoseOpenNowAndAProviderThatSaysNothingDoesNotHoldTheCommand() async throws {
        let demo = DemoProvider(kind: .claude, date: now)
        let accounts = await demo.accounts()
        let states = await TerminalAccounts.load(accounts, from: [demo], now: { TestFixtures.date })
        let personal = try #require(states.first { $0.account.name == "personal" })
        #expect(personal.activity.workingCount == 2)
        let studio = try #require(states.first { $0.account.name == "studio" })
        #expect(studio.usageError == .sessionExpired)
        #expect(studio.usage != nil)

        let silent = SilentProvider(account: TestFixtures.account("silent", kind: .codex))
        let started = ContinuousClock.now
        let quiet = await TerminalAccounts.load([silent.account], from: [silent], activityTimeout: .milliseconds(20))
        #expect(quiet.map(\.activity) == [.none])
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}

/// A provider whose activity never arrives.
private struct SilentProvider: AccountProvider {
    let kind = ProviderKind.codex
    let account: Account

    func accounts() async -> [Account] { [account] }
    func cachedUsage(for account: Account) async -> UsageSnapshot? { nil }
    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot { throw .signedOut }
    func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> { AsyncStream { _ in } }
    func statistics(for account: Account, days: Int) async -> UsageStatistics { .empty }
}
