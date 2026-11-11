import AgentBarCore
import CoreGraphics
import Foundation

@MainActor
enum ProviderGlyph {
    /// The mark of a provider, or of every provider for `nil`, inside the circle inscribed in `rect`, whose
    /// origin is its top left corner. `phase` runs from 0 to 1 while there is work and is `nil` at rest.
    static func path(for kind: ProviderKind?, in rect: CGRect, phase: Double? = nil) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        let frame = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: radius, y: radius)
        let turn = frame.rotated(by: 2 * .pi * (phase ?? 0))
        let path = CGMutablePath()
        switch kind {
        case .claude: path.addPath(claude, transform: turn)
        case .codex: path.addPath(codex, transform: turn)
        case nil:
            // Three bars; at work a wave runs through their heights four times per cycle.
            let halfWidth = 0.08
            for index in -1...1 {
                let wave = phase.map { sin(2 * .pi * (4 * $0 - Double(index) / 3)) } ?? 0
                let halfHeight = 0.5 + 0.2 * wave
                let bar = CGRect(
                    x: 0.5 * Double(index) - halfWidth, y: -halfHeight, width: 2 * halfWidth, height: 2 * halfHeight
                )
                path.addRoundedRect(in: bar, cornerWidth: halfWidth, cornerHeight: halfWidth, transform: frame)
            }
        }
        return path
    }

    // Outlines adapted from Simple Icons; see THIRD_PARTY_NOTICES.md for licenses and brand restrictions.
    // Rewritten as absolute lines and curves in a circle of radius 1:
    // the Claude spark around the point where its rays meet, and the OpenAI knot at the same visual size.
    private static let claude = outline("""
        M -0.586 0.271 L -0.242 0.078 L -0.236 0.061 L -0.242 0.052 L -0.259 0.052 L -0.316 0.048 L -0.513 0.043 L
        -0.683 0.036 L -0.848 0.027 L -0.890 0.018 L -0.928 -0.033 L -0.924 -0.059 L -0.890 -0.082 L -0.840 -0.078 L
        -0.729 -0.070 L -0.563 -0.059 L -0.443 -0.052 L -0.265 -0.033 L -0.236 -0.033 L -0.232 -0.045 L -0.242
        -0.052 L -0.250 -0.059 L -0.421 -0.175 L -0.607 -0.298 L -0.704 -0.369 L -0.757 -0.405 L -0.783 -0.438 L
        -0.795 -0.512 L -0.747 -0.565 L -0.683 -0.560 L -0.667 -0.556 L -0.602 -0.506 L -0.463 -0.398 L -0.281
        -0.265 L -0.255 -0.243 L -0.244 -0.250 L -0.243 -0.255 L -0.255 -0.275 L -0.353 -0.453 L -0.459 -0.635 L
        -0.506 -0.710 L -0.518 -0.755 C -0.522 -0.774 -0.526 -0.789 -0.526 -0.808 L -0.471 -0.882 L -0.441 -0.892 L
        -0.368 -0.882 L -0.338 -0.856 L -0.293 -0.752 L -0.220 -0.590 L -0.107 -0.369 L -0.073 -0.304 L -0.056
        -0.243 L -0.049 -0.225 L -0.038 -0.225 L -0.038 -0.235 L -0.028 -0.360 L -0.011 -0.512 L 0.006 -0.709 L
        0.011 -0.764 L 0.039 -0.830 L 0.093 -0.866 L 0.136 -0.846 L 0.171 -0.796 L 0.166 -0.764 L 0.145 -0.629 L
        0.104 -0.417 L 0.078 -0.276 L 0.093 -0.276 L 0.111 -0.293 L 0.183 -0.388 L 0.303 -0.539 L 0.356 -0.599 L
        0.418 -0.664 L 0.458 -0.696 L 0.533 -0.696 L 0.588 -0.614 L 0.563 -0.529 L 0.486 -0.430 L 0.422 -0.347 L
        0.330 -0.223 L 0.272 -0.124 L 0.278 -0.116 L 0.291 -0.118 L 0.499 -0.162 L 0.612 -0.182 L 0.746 -0.205 L
        0.806 -0.177 L 0.813 -0.148 L 0.789 -0.089 L 0.646 -0.054 L 0.478 -0.020 L 0.227 0.039 L 0.224 0.041 L 0.228
        0.045 L 0.341 0.056 L 0.389 0.059 L 0.507 0.059 L 0.727 0.075 L 0.784 0.113 L 0.819 0.160 L 0.813 0.195 L
        0.724 0.240 L 0.605 0.212 L 0.326 0.145 L 0.231 0.122 L 0.218 0.122 L 0.218 0.129 L 0.297 0.207 L 0.443
        0.339 L 0.626 0.509 L 0.635 0.551 L 0.612 0.584 L 0.587 0.581 L 0.426 0.460 L 0.364 0.405 L 0.224 0.287 L
        0.215 0.287 L 0.215 0.300 L 0.247 0.347 L 0.418 0.604 L 0.427 0.682 L 0.414 0.708 L 0.370 0.723 L 0.321
        0.715 L 0.222 0.574 L 0.118 0.417 L 0.035 0.275 L 0.025 0.281 L -0.024 0.809 L -0.047 0.836 L -0.100 0.857 L
        -0.144 0.823 L -0.168 0.769 L -0.144 0.661 L -0.116 0.521 L -0.093 0.409 L -0.072 0.271 L -0.060 0.225 L
        -0.061 0.222 L -0.071 0.223 L -0.175 0.367 L -0.334 0.581 L -0.460 0.716 L -0.490 0.727 L -0.542 0.700 L
        -0.537 0.652 L -0.508 0.609 L -0.334 0.388 L -0.229 0.251 L -0.161 0.172 L -0.162 0.160 L -0.166 0.160 L
        -0.628 0.460 L -0.710 0.471 L -0.745 0.438 L -0.741 0.383 L -0.724 0.366 L -0.585 0.270 Z
        """)

    private static let codex = outline("""
        M 0.729 -0.154 C 0.767 -0.270 0.754 -0.397 0.692 -0.502 C 0.599 -0.664 0.413 -0.747 0.231 -0.708 C 0.128
        -0.822 -0.028 -0.873 -0.178 -0.841 C -0.328 -0.809 -0.450 -0.700 -0.497 -0.554 C -0.617 -0.529 -0.720 -0.455
        -0.781 -0.348 C -0.874 -0.187 -0.853 0.016 -0.728 0.154 C -0.767 0.270 -0.753 0.397 -0.692 0.502 C -0.599
        0.664 -0.412 0.747 -0.230 0.708 C -0.149 0.799 -0.033 0.851 0.089 0.850 C 0.276 0.851 0.441 0.730 0.498
        0.552 C 0.618 0.528 0.721 0.453 0.782 0.347 C 0.874 0.186 0.853 -0.016 0.729 -0.154 Z M 0.089 0.739 C 0.015
        0.739 -0.057 0.713 -0.115 0.665 L -0.105 0.660 L 0.234 0.464 C 0.251 0.454 0.262 0.436 0.262 0.416 L 0.262
        -0.061 L 0.405 0.021 C 0.406 0.022 0.407 0.023 0.408 0.025 L 0.408 0.421 C 0.407 0.596 0.265 0.739 0.089
        0.739 Z M -0.595 0.447 C -0.633 0.382 -0.646 0.307 -0.633 0.233 L -0.623 0.239 L -0.284 0.435 C -0.267 0.445
        -0.246 0.445 -0.229 0.435 L 0.185 0.196 L 0.185 0.361 C 0.185 0.363 0.184 0.365 0.183 0.366 L -0.160 0.563 C
        -0.313 0.651 -0.507 0.599 -0.595 0.447 Z M -0.684 -0.291 C -0.647 -0.356 -0.587 -0.405 -0.517 -0.431 L
        -0.517 -0.028 C -0.517 -0.009 -0.507 0.010 -0.489 0.020 L -0.077 0.257 L -0.220 0.340 C -0.222 0.341 -0.224
        0.341 -0.226 0.340 L -0.568 0.143 C -0.720 0.055 -0.772 -0.140 -0.684 -0.292 Z M 0.492 -0.018 L 0.078 -0.258
        L 0.221 -0.340 C 0.223 -0.341 0.224 -0.341 0.226 -0.340 L 0.568 -0.142 C 0.675 -0.081 0.737 0.037 0.727
        0.160 C 0.716 0.283 0.636 0.389 0.520 0.432 L 0.520 0.030 C 0.520 0.010 0.509 -0.008 0.492 -0.018 Z M 0.634
        -0.232 L 0.624 -0.238 L 0.286 -0.435 C 0.269 -0.445 0.247 -0.445 0.230 -0.435 L -0.184 -0.196 L -0.184
        -0.362 C -0.184 -0.363 -0.183 -0.365 -0.182 -0.366 L 0.161 -0.563 C 0.268 -0.625 0.401 -0.619 0.502 -0.549 C
        0.604 -0.478 0.655 -0.355 0.634 -0.233 Z M -0.262 0.061 L -0.405 -0.021 C -0.406 -0.022 -0.407 -0.024 -0.408
        -0.025 L -0.408 -0.420 C -0.407 -0.543 -0.336 -0.656 -0.224 -0.708 C -0.112 -0.761 0.020 -0.744 0.115 -0.665
        L 0.105 -0.659 L -0.234 -0.463 C -0.251 -0.453 -0.261 -0.435 -0.261 -0.415 Z M -0.184 -0.106 L 0.000 -0.213
        L 0.185 -0.106 L 0.185 0.106 L 0.001 0.212 L -0.184 0.106 Z
        """)

    private static func outline(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var values = data.split(whereSeparator: \.isWhitespace).makeIterator()
        func point() -> CGPoint {
            CGPoint(x: Double(values.next() ?? "") ?? 0, y: Double(values.next() ?? "") ?? 0)
        }
        while let command = values.next() {
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C":
                let (control1, control2) = (point(), point())
                path.addCurve(to: point(), control1: control1, control2: control2)
            default: path.closeSubpath()
            }
        }
        return path
    }
}
