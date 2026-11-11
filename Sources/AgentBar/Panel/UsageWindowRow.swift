import AgentBarCore
import SwiftUI

struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Text(window.title).lineLimit(1).frame(width: 36, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.7))
                            .frame(width: geometry.size.width * (window.usedPercent.isFinite ? window.usedPercent / 100 : 0))
                    }
            }
            .frame(height: 3)
            Text(DisplayFormat.percent(window.usedPercent))
                .frame(width: 33, alignment: .trailing)
            Text(DisplayFormat.reset(window.resetsAt, now: now))
                .foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 11)).monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.title), \(DisplayFormat.percent(window.usedPercent)) used")
        .accessibilityValue(window.resetsAt == nil ? "Reset time unknown" : "Resets in \(DisplayFormat.reset(window.resetsAt, now: now))")
        .help(window.resetsAt.map { "Resets \(DisplayFormat.date($0))" } ?? "Reset time unknown")
    }
}
