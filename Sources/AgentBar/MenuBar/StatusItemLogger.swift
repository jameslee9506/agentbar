import Foundation

@MainActor
final class StatusItemLogger {
    private var lastLine: String?
    private let output: (String) -> Void

    init(output: @escaping (String) -> Void = {
        FileHandle.standardOutput.write(Data(($0 + "\n").utf8))
    }) {
        self.output = output
    }

    func record(_ plan: [StatusItemDescriptor]) {
        // Plans that differ only in what the line leaves out are not logged again.
        let line = Self.line(for: plan)
        guard line != lastLine else { return }
        lastLine = line
        output(line)
    }

    static func line(for plan: [StatusItemDescriptor]) -> String {
        let items = plan.map { item in
            let provider = item.provider?.commandName ?? "combined"
            var label = provider
            // Labels may be derived from config directory names. Never emit an email label.
            if let name = item.name, !name.contains("@"), let shown = item.displayedName {
                let safeName = shown.components(separatedBy: .controlCharacters).joined(separator: " ")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !safeName.isEmpty, safeName != provider { label += ":\(safeName)" }
            }
            if item.workingCount > 0 { label += " working=\(item.workingCount)" }
            if let usage = item.weeklyUsage { label += " week=\(usage)" }
            return label
        }
        return "items: " + (items.isEmpty ? "none" : items.joined(separator: " · "))
    }
}
