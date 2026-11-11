import AgentBarCore
import SwiftUI

struct SessionRow: View {
    let session: AgentSession
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(session.state == .working ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(DisplayFormat.directory(session.directory)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(duration).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 11))
        .help(session.directory ?? "Session")
        .accessibilityLabel("\(DisplayFormat.directory(session.directory)), \(session.state.rawValue), \(duration)")
    }

    private var duration: String {
        guard session.state == .working else { return "Idle" }
        return session.since.map { DisplayFormat.duration(now.timeIntervalSince($0)) } ?? "Working"
    }
}
