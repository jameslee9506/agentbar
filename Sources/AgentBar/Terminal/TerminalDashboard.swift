import AgentBarCore
import Foundation

/// The accounts as the panel shows them, drawn as cards of text for a terminal.
struct TerminalDashboard {
    let accounts: [AccountState]
    let now: Date

    /// Between the cards of a row.
    private static let gap = 2
    /// The narrowest card has room for every column of a usage row; a wider one has longer bars.
    private static let cardWidths = 46...58

    func text(width: Int, colors: Bool) -> String {
        lines(width: width).map { $0.string(colors: colors) }.joined(separator: "\n")
    }

    func lines(width: Int) -> [TerminalLine] {
        guard !accounts.isEmpty else { return [] }
        // As many cards in a row as fit, then as few as fill the same number of rows.
        let fitting = max(1, (width + Self.gap) / (Self.cardWidths.lowerBound + Self.gap))
        let rows = (accounts.count + fitting - 1) / fitting
        let columns = (accounts.count + rows - 1) / rows
        let layout = layout(card: max(24, min(Self.cardWidths.upperBound, (width - Self.gap * (columns - 1)) / columns)))
        let cards = accounts.map { card($0, layout) }
        var lines: [TerminalLine] = []
        for start in stride(from: 0, to: cards.count, by: columns) {
            let row = cards[start..<min(start + columns, cards.count)]
            // The cards of a row end on the same line.
            let height = row.map { $0.rows.count }.max() ?? 0
            let drawn = row.map { $0.lines(rows: height) }
            for index in 0..<height + 3 {
                var line = TerminalLine()
                for (offset, card) in drawn.enumerated() {
                    if offset > 0 { line.append(String(repeating: " ", count: Self.gap)) }
                    line.append(card[index])
                }
                lines.append(line)
            }
        }
        return lines
    }

    /// The columns of a usage row, the same in every card so that the bars line up.
    private struct Layout {
        let card: Int
        let title: Int
        let bar: Int
        /// 0 where the cards are too narrow for the reset times.
        let reset: Int

        /// Inside a card's borders and the space next to each.
        var inner: Int { card - 4 }
    }

    private struct Card {
        let top: TerminalLine
        /// Usage, status, and sessions.
        let rows: [TerminalLine]
        /// The tokens, kept on the last line.
        let footer: TerminalLine
        let width: Int

        /// The card with room for `count` rows: two more lines than that for its borders, one for its footer.
        func lines(rows count: Int) -> [TerminalLine] {
            let blank = Array(repeating: TerminalLine(), count: count - rows.count)
            let body = (rows + blank + [footer]).map { row in
                var line = TerminalLine("│ ", .dim)
                line.append(row)
                line.pad(to: width - 2)
                line.append(" │", .dim)
                return line
            }
            return [top] + body + [TerminalLine("╰" + String(repeating: "─", count: width - 2) + "╯", .dim)]
        }
    }

    private func layout(card: Int) -> Layout {
        let windows = accounts.flatMap { $0.snapshot(at: now)?.windows ?? [] }
        let title = min(10, windows.map { $0.title.terminalSafe.terminalWidth }.max() ?? 0)
        let reset = windows.map { resetText($0).count }.max() ?? 0
        // Beside the bar: the title, the percentage in four cells, and a space before each.
        let bar = card - 4 - title - 6
        if reset > 0, bar - reset - 2 >= 8 {
            return Layout(card: card, title: title, bar: bar - reset - 2, reset: reset)
        }
        return Layout(card: card, title: title, bar: max(1, bar), reset: 0)
    }

    private func card(_ state: AccountState, _ layout: Layout) -> Card {
        let windows = state.snapshot(at: now)?.windows ?? []
        var rows = windows.map { usageRow($0, layout) }
        if windows.isEmpty, state.usageError == nil { rows.append(TerminalLine("No usage data", .dim)) }
        if let status = DisplayFormat.status(state, now: now) {
            rows.append(TerminalLine(status.terminalTruncated(to: layout.inner), state.usageError == nil ? .dim : .yellow))
        }
        rows += state.activity.sessions.map { sessionRow($0, layout) }
        let tokens = DisplayFormat.tokenSummary(state.statistics, now: now).terminalTruncated(to: layout.inner)
        return Card(top: title(state, width: layout.card), rows: rows, footer: TerminalLine(tokens, .dim), width: layout.card)
    }

    /// The top border, with the provider and the account's name in it and the plan at its end.
    private func title(_ state: AccountState, width: Int) -> TerminalLine {
        let provider = state.id.provider
        let name = state.account.name.terminalSafe
        let plan = state.account.plan?.terminalSafe ?? ""
        // What the corners, the separator, and one cell of border at least leave for the name.
        let room = width - provider.displayName.count - 10
        let showsPlan = !plan.isEmpty && name.terminalWidth + plan.terminalWidth + 2 <= room
        var line = TerminalLine("╭─ ", .dim)
        line.append(provider.displayName, provider == .claude ? .claude : .bold)
        line.append(" · ", .dim)
        line.append(name.terminalTruncated(to: room - (showsPlan ? plan.terminalWidth + 2 : 0)), .bold)
        line.append(" ")
        let end = showsPlan ? " \(plan) ─╮" : "─╮"
        line.append(String(repeating: "─", count: max(0, width - line.width - end.terminalWidth)) + end, .dim)
        return line
    }

    private func usageRow(_ window: UsageWindow, _ layout: Layout) -> TerminalLine {
        let used = window.usedPercent.isFinite ? window.usedPercent : 0
        let level: TerminalStyle = used >= 90 ? .red : used >= 70 ? .yellow : .plain
        // Any usage at all shows in the bar.
        let filled = used > 0 ? max(1, Int((used / 100 * Double(layout.bar)).rounded())) : 0
        let percent = DisplayFormat.percent(window.usedPercent)
        var line = TerminalLine(window.title.terminalSafe.terminalTruncated(to: layout.title))
        line.pad(to: layout.title + 1)
        line.append(String(repeating: "━", count: filled), level)
        line.append(String(repeating: "─", count: layout.bar - filled), .dim)
        line.pad(to: layout.title + layout.bar + 6 - percent.count)
        line.append(percent, level)
        if layout.reset > 0 { line.append("  " + resetText(window), .dim) }
        return line
    }

    private func resetText(_ window: UsageWindow) -> String {
        guard let date = window.resetsAt, date > now else { return "" }
        return "resets in " + DisplayFormat.reset(date, now: now)
    }

    private func sessionRow(_ session: AgentSession, _ layout: Layout) -> TerminalLine {
        let working = session.state == .working
        let time = DisplayFormat.sessionTime(session, now: now)
        // The mark, the directory, and two cells at least before the time.
        let directory = DisplayFormat.directory(session.directory).terminalSafe
            .terminalTruncated(to: layout.inner - 4 - time.count)
        var line = TerminalLine(working ? "●" : "○", working ? .green : .dim)
        line.append(" ")
        line.append(directory, working ? .plain : .dim)
        line.pad(to: layout.inner - time.count)
        line.append(time, .dim)
        return line
    }
}
