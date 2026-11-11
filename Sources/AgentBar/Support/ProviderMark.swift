import AgentBarCore
import SwiftUI

struct ProviderMark: View {
    let kind: ProviderKind
    var isWorking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.showsWorkingMotion) private var showsWorkingMotion

    var body: some View {
        let moves = isWorking && showsWorkingMotion && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / WorkingMotion.frameRate, paused: !moves)) { timeline in
            Canvas { context, size in
                let path = ProviderGlyph.path(
                    for: kind, in: CGRect(origin: .zero, size: size),
                    phase: moves ? WorkingMotion.phase(at: timeline.date) : nil
                )
                context.fill(Path(path), with: kind == .claude ? .color(Self.claudeOrange) : .foreground)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(kind.displayName)
    }

    private static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
}
