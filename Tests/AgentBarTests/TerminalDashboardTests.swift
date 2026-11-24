@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

struct TerminalDashboardTests {
    private let now = TestFixtures.date

    @Test func aCardShowsUsageSessionsAndTokensAsThePanelDoes() {
        var state = AccountState(account: TestFixtures.account("alpha"))
        state.usage = UsageSnapshot(windows: [
            UsageWindow(id: "session", title: "5h", usedPercent: 43, resetsAt: now.addingTimeInterval(7_680)),
            UsageWindow(id: "weekly", title: "Week", usedPercent: 68, resetsAt: now.addingTimeInterval(259_200)),
        ], capturedAt: now)
        state.lastSuccessfulRefresh = now
        state.activity = AccountActivity(sessions: [
            AgentSession(id: "a", state: .working, directory: "/synthetic/project", since: now.addingTimeInterval(-480)),
            AgentSession(id: "b", state: .idle, directory: "/synthetic/project"),
        ])
        let today = Calendar.current.startOfDay(for: now)
        state.statistics = UsageStatistics(days: [
            DailyUsage(day: today.addingTimeInterval(-3 * 86_400), byModel: ["test-model": TokenCount(input: 2_000_000)]),
            DailyUsage(day: today, byModel: ["test-model": TokenCount(input: 1_500)]),
        ])
        let text = TerminalDashboard(accounts: [state], now: now).text(width: 46, colors: false)
        #expect(text.components(separatedBy: "\n") == [
            "Claude Code",
            "╭─ alpha " + String(repeating: "─", count: 29) + " Test ─╮",
            "│ 5h   " + bar(6, of: 15) + "  43%  resets in 2h 8m │",
            "│ Week " + bar(10, of: 15) + "  68%  resets in 3d    │",
            "│ ● project" + spaces(31) + "8m │",
            "│ ○ project" + spaces(29) + "Idle │",
            "│ Tokens  1.5K today · 2M in 7d" + spaces(13) + " │",
            "╰" + String(repeating: "─", count: 44) + "╯",
        ])
    }

    @Test func staleAndMissingUsageIsSaid() {
        var stale = AccountState(account: TestFixtures.account("alpha"))
        stale.usage = TestFixtures.snapshot(40, at: now.addingTimeInterval(-600))
        stale.usageError = .sessionExpired
        var signedOut = AccountState(account: TestFixtures.account("beta"))
        signedOut.usageError = .signedOut
        let unknown = AccountState(account: TestFixtures.account("gamma"))
        let text = TerminalDashboard(accounts: [stale, signedOut, unknown], now: now).text(width: 46, colors: false)
        #expect(text.contains("│ Stale · Sign-in expired "))
        #expect(text.contains("│ Signed out "))
        #expect(text.contains("│ No usage data "))
        // A window whose reset has passed is empty, and no longer says when it resets.
        var passed = AccountState(account: TestFixtures.account("delta"))
        passed.usage = TestFixtures.snapshot(90, reset: now.addingTimeInterval(-1))
        let rolled = TerminalDashboard(accounts: [passed], now: now).text(width: 46, colors: false)
        #expect(rolled.contains("  0% "))
        #expect(!rolled.contains("resets"))
    }

    @Test func cardsFillTheWidthInEvenRows() {
        let accounts = (1...5).map { state("account-\($0)", percent: Double($0 * 10)) }
        let dashboard = TerminalDashboard(accounts: accounts, now: now)
        func cardsPerRow(_ width: Int) -> [Int] {
            dashboard.lines(width: width).map { $0.string(colors: false) }
                .filter { $0.hasPrefix("╭") }.map { $0.count { $0 == "╭" } }
        }
        #expect(cardsPerRow(40) == [1, 1, 1, 1, 1])
        #expect(cardsPerRow(94) == [2, 2, 1])
        // Four would fit: three and two fill the same two rows.
        #expect(cardsPerRow(200) == [3, 2])
        // No line is wider than the terminal, and the cards of a row are equally high and wide.
        for width in [46, 94, 143, 200] {
            let lines = dashboard.lines(width: width)
            #expect(lines.allSatisfy { $0.width <= width })
            #expect(Set(lines[1...4].map(\.width)).count == 1)
        }
        #expect(TerminalDashboard(accounts: [], now: now).lines(width: 80).isEmpty)
    }

    @Test func narrowCardsLeaveOutTheResetTimes() {
        let dashboard = TerminalDashboard(accounts: [state("alpha", percent: 43)], now: now)
        #expect(dashboard.text(width: 80, colors: false).contains("43%  resets in 2h 8m"))
        let narrow = dashboard.lines(width: 30)
        #expect(!narrow.contains { $0.string(colors: false).contains("resets") })
        #expect(narrow.contains { $0.string(colors: false).contains("43% │") })
        #expect(narrow.dropFirst().allSatisfy { $0.width == 30 })
    }

    @Test func colorsMarkHighUsageAndWorkingSessionsOnlyWhenAsked() {
        var working = state("alpha", percent: 72)
        working.activity = TestFixtures.activity(.working)
        let dashboard = TerminalDashboard(accounts: [working, state("beta", percent: 95), state("gamma", percent: 10)], now: now)
        let plain = dashboard.text(width: 46, colors: false)
        #expect(!plain.contains("\u{1B}"))
        // The unused part of a bar is dim, and without colors a line of its own.
        #expect(plain.contains(" " + bar(16, of: 17) + "  95% "))
        let colored = dashboard.text(width: 46, colors: true)
        #expect(colored.contains("\u{1B}[31m" + String(repeating: "▆", count: 16) + "\u{1B}[0m\u{1B}[2m▆\u{1B}[0m"))
        #expect(colored.contains("\u{1B}[33m72%\u{1B}[0m"))
        #expect(colored.contains("\u{1B}[31m95%\u{1B}[0m"))
        #expect(colored.contains(" 10%"))
        #expect(colored.contains("\u{1B}[32m●\u{1B}[0m"))
        #expect(colored.contains("\u{1B}[1;38;5;173mClaude Code\u{1B}[0m"))
    }

    @Test func namesNeverControlTheTerminalAndWideOnesKeepTheBorders() {
        let account = Account(
            id: AccountID(provider: .codex, home: "test-odd"), name: "odd\u{1B}[2J\nname",
            home: URL(fileURLWithPath: "/synthetic/odd"), plan: "P\u{7}ro"
        )
        var odd = AccountState(account: account)
        odd.usage = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "We\tek", usedPercent: 5)], capturedAt: now)
        odd.lastSuccessfulRefresh = now
        odd.activity = AccountActivity(sessions: [
            AgentSession(id: "a", state: .working, directory: "/synthetic/메모장 👍", since: now),
            AgentSession(id: "b", state: .idle, directory: "/synthetic/" + String(repeating: "x", count: 80)),
        ])
        let lines = TerminalDashboard(accounts: [odd], now: now).lines(width: 46)
        let text = lines.map { $0.string(colors: true) }.joined(separator: "\n")
        #expect(text.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control || $0 == "\n" || $0 == "\u{1B}" })
        #expect(!text.contains("\u{1B}[2J"))
        #expect(lines.count == 7)
        #expect(lines.dropFirst().allSatisfy { $0.width == 46 })
        #expect(text.contains("메모장 👍"))
        #expect(lines[4].string(colors: false).hasSuffix("x…  Idle │"))
    }

    @Test func accountsAreGroupedUnderTheirProvider() {
        // Each provider where its first account is, with its accounts in the order given.
        let dashboard = TerminalDashboard(accounts: [
            state("beta", percent: 10), state("codex", percent: 20, kind: .codex), state("alpha", percent: 30),
        ], now: now)
        let text = dashboard.lines(width: 200).map { $0.string(colors: false) }
        #expect(text.filter { !"╭│╰".contains($0.first ?? " ") } == ["Claude Code", "", "Codex"])
        let titles = text.filter { $0.hasPrefix("╭") }
        #expect(titles.count == 2)
        #expect(titles[0].hasPrefix("╭─ beta ") && titles[0].contains("╮  ╭─ alpha "))
        #expect(titles[1].hasPrefix("╭─ codex "))
        // A provider with fewer cards has cards as wide as the others.
        func bottoms(_ width: Int) -> [Int] {
            dashboard.lines(width: width).filter { $0.string(colors: false).hasPrefix("╰") }.map(\.width)
        }
        #expect(bottoms(200) == [58 + 2 + 58, 58])
        #expect(bottoms(100) == [49 + 2 + 49, 49])
        let colored = dashboard.text(width: 200, colors: true)
        #expect(colored.hasPrefix("\u{1B}[1;38;5;173mClaude Code\u{1B}[0m\n"))
        #expect(colored.contains("\n\n\u{1B}[1mCodex\u{1B}[0m\n"))
    }

    private func state(_ name: String, percent: Double, kind: ProviderKind = .claude) -> AccountState {
        var state = AccountState(account: TestFixtures.account(name, kind: kind))
        state.usage = TestFixtures.snapshot(percent, at: now, reset: now.addingTimeInterval(7_680))
        state.lastSuccessfulRefresh = now
        return state
    }

    /// A bar as it reads without colors.
    private func bar(_ filled: Int, of width: Int) -> String {
        String(repeating: "▆", count: filled) + String(repeating: "▁", count: width - filled)
    }

    private func spaces(_ count: Int) -> String { String(repeating: " ", count: count) }
}

struct TerminalLineTests {
    @Test func widthsAreMeasuredInCells() {
        #expect("agentbar".terminalWidth == 8)
        #expect("메모".terminalWidth == 4)
        // As file names spell it, in conjoining letters.
        #expect("메모".decomposedStringWithCanonicalMapping.terminalWidth == 4)
        #expect("e\u{301}".terminalWidth == 1)
        #expect("👍".terminalWidth == 2)
        #expect("❤\u{FE0F}".terminalWidth == 2)
        #expect("▆▁─●○│╭".terminalWidth == 7)
        var line = TerminalLine("메모", .bold)
        line.pad(to: 6)
        line.append("x")
        #expect(line.width == 7)
        #expect(line.string(colors: false) == "메모  x")
        #expect(line.string(colors: true) == "\u{1B}[1m메모\u{1B}[0m  x")
    }

    @Test func textThatOnlyItsStyleSetsApartHasAnotherWithoutColors() {
        var line = TerminalLine("▆▆")
        line.append("▆▆▆", .dim, uncolored: "▁▁▁")
        #expect(line.width == 5)
        #expect(line.string(colors: true) == "▆▆\u{1B}[2m▆▆▆\u{1B}[0m")
        #expect(line.string(colors: false) == "▆▆▁▁▁")
    }

    @Test func longTextEndsInAnEllipsisWithinItsCells() {
        #expect("agentbar".terminalTruncated(to: 8) == "agentbar")
        #expect("agentbar".terminalTruncated(to: 5) == "agen…")
        #expect("메모장".terminalTruncated(to: 5) == "메모…")
        // Half of a wide character does not fit.
        #expect("메모장".terminalTruncated(to: 4) == "메…")
        #expect("agentbar".terminalTruncated(to: 1) == "…")
        #expect("agentbar".terminalTruncated(to: 0) == "")
    }

    @Test func controlCharactersBecomeSpaces() {
        #expect("a\u{1B}[0m\nb\tc".terminalSafe == "a [0m b c")
        #expect(TerminalLine("a\u{1B}b").string(colors: true) == "a b")
    }
}
