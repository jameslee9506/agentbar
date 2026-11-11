import AgentBarCore
import AppKit

/// The mark of a status item while its account is working. Core Animation moves it, so the app draws no
/// frames and the item is not redrawn: redrawing a status item takes milliseconds of work in the app.
final class StatusItemMotionView: NSView {
    private let provider: ProviderKind?
    private let mark = CAShapeLayer()

    init(provider: ProviderKind?) {
        self.provider = provider
        super.init(frame: StatusItemImage.markFrame)
        wantsLayer = true
        mark.frame = bounds
        mark.path = ProviderGlyph.path(for: provider, in: bounds)
        mark.actions = ["fillColor": NSNull()]
        layer?.addSublayer(mark)
    }

    required init?(coder: NSCoder) { nil }

    /// Puts the mark where the image of `button`, drawn without one, leaves room for it.
    func install(in button: NSStatusBarButton) {
        translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(self)
        // The button centers its image.
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: button.centerXAnchor, constant: -(button.image?.size.width ?? 0) / 2),
            centerYAnchor.constraint(equalTo: button.centerYAnchor),
            widthAnchor.constraint(equalToConstant: bounds.width),
            heightAnchor.constraint(equalToConstant: bounds.height),
        ])
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    /// Runs with the appearance of the menu bar, where a label has the color of a template image.
    override func updateLayer() { mark.fillColor = NSColor.labelColor.cgColor }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A layer loses its animations when it leaves a window.
    override func viewDidMoveToWindow() {
        guard window != nil else { return }
        let steps = 60
        let motion = CAKeyframeAnimation(keyPath: "path")
        motion.values = (0...steps).map {
            ProviderGlyph.path(for: provider, in: bounds, phase: Double($0) / Double(steps))
        }
        motion.duration = WorkingMotion.period
        motion.repeatCount = .infinity
        motion.preferredFrameRateRange = CAFrameRateRange(
            minimum: 10, maximum: 15, preferred: Float(WorkingMotion.frameRate)
        )
        // Start where the clock is, as every working mark does.
        motion.timeOffset = WorkingMotion.phase(at: .now) * WorkingMotion.period
        mark.add(motion, forKey: "working")
    }
}
