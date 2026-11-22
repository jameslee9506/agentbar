import Foundation

/// How a run of terminal text looks: the parameters of its SGR sequence.
struct TerminalStyle: Equatable {
    let parameters: String

    static let plain = TerminalStyle(parameters: "")
    static let bold = TerminalStyle(parameters: "1")
    static let dim = TerminalStyle(parameters: "2")
    static let green = TerminalStyle(parameters: "32")
    static let yellow = TerminalStyle(parameters: "33")
    static let red = TerminalStyle(parameters: "31")
    /// Bold, in the orange of the Claude mark.
    static let claude = TerminalStyle(parameters: "1;38;5;173")
}

/// One line of terminal text in styled runs, measured in the cells it takes.
struct TerminalLine: Equatable {
    private struct Run: Equatable {
        let text: String
        let style: TerminalStyle
    }

    private var runs: [Run] = []
    private(set) var width = 0

    init() {}

    init(_ text: String, _ style: TerminalStyle = .plain) {
        append(text, style)
    }

    mutating func append(_ text: String, _ style: TerminalStyle = .plain) {
        let text = text.terminalSafe
        guard !text.isEmpty else { return }
        runs.append(Run(text: text, style: style))
        width += text.terminalWidth
    }

    mutating func append(_ line: TerminalLine) {
        runs += line.runs
        width += line.width
    }

    /// Fills the line with spaces up to `width` cells.
    mutating func pad(to width: Int) {
        append(String(repeating: " ", count: max(0, width - self.width)))
    }

    func string(colors: Bool) -> String {
        runs.map { run in
            colors && run.style != .plain ? "\u{1B}[\(run.style.parameters)m\(run.text)\u{1B}[0m" : run.text
        }.joined()
    }
}

extension String {
    /// The text with a space for each character a terminal would act on instead of show.
    var terminalSafe: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// The cells the text takes in a terminal.
    var terminalWidth: Int { reduce(0) { $0 + $1.terminalWidth } }

    /// The text cut to `width` cells, ending in an ellipsis where it was longer.
    func terminalTruncated(to width: Int) -> String {
        guard terminalWidth > width else { return self }
        var kept = ""
        var cells = 0
        for character in self {
            guard cells + character.terminalWidth < width else { break }
            kept.append(character)
            cells += character.terminalWidth
        }
        return width > 0 ? kept + "…" : ""
    }
}

private extension Character {
    var terminalWidth: Int {
        // An emoji variation selector widens the character before it.
        if unicodeScalars.contains(where: { $0.value == 0xFE0F }) { return 2 }
        return unicodeScalars.reduce(0) { max($0, $1.terminalWidth) }
    }
}

private extension Unicode.Scalar {
    var terminalWidth: Int {
        switch properties.generalCategory {
        case .control, .format, .nonspacingMark, .enclosingMark, .lineSeparator, .paragraphSeparator: return 0
        default: break
        }
        if properties.isEmojiPresentation { return 2 }
        switch value {
        // Hangul, CJK, and the fullwidth forms.
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}
