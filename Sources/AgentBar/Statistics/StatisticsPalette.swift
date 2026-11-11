import SwiftUI

enum StatisticsPalette {
    static let colors: [Color] = [.blue, .teal, .indigo, .orange, .purple, .green, .pink, .brown]

    static func color(at index: Int) -> Color { colors[index % colors.count].opacity(0.8) }
}
