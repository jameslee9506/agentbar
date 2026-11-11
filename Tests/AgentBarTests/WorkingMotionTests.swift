@testable import AgentBar
import AgentBarCore
import AppKit
import Testing

@MainActor
struct WorkingMotionTests {
    @Test func phaseFollowsTheClockAndWrapsEveryPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000 * WorkingMotion.period)
        #expect(WorkingMotion.phase(at: start) == 0)
        #expect(abs(WorkingMotion.phase(at: start.addingTimeInterval(WorkingMotion.period / 4)) - 0.25) < 1e-9)
        #expect(abs(WorkingMotion.phase(at: start.addingTimeInterval(WorkingMotion.period * 1.75)) - 0.75) < 1e-9)
        #expect((0..<1).contains(WorkingMotion.phase(at: Date(timeIntervalSinceReferenceDate: -1.25))))
    }

    @Test func marksMoveWithoutLeavingTheirBox() {
        let box = CGRect(x: 4, y: 6, width: 18, height: 18)
        for kind in [ProviderKind.claude, .codex, nil] {
            let rest = ProviderGlyph.path(for: kind, in: box)
            #expect(!rest.isEmpty)
            #expect(box.contains(rest.boundingBoxOfPath))
            for step in 0..<24 {
                let moving = ProviderGlyph.path(for: kind, in: box, phase: Double(step) / 24)
                #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(moving.boundingBoxOfPath))
            }
            #expect(ProviderGlyph.path(for: kind, in: box, phase: 0.1) != rest)
        }
        // A provider mark at rest stands upright, as at the start of a turn.
        #expect(ProviderGlyph.path(for: .claude, in: box, phase: 0) == ProviderGlyph.path(for: .claude, in: box))
    }

    @Test func movingMarkTakesThePlaceTheImageLeavesFree() throws {
        _ = NSApplication.shared
        for provider in [ProviderKind.claude, .codex, nil] {
            let descriptor = StatusItemDescriptor(
                id: .overview, provider: provider, name: provider == nil ? nil : "work", workingCount: 2,
                number: .workingSessions, weeklyUsage: nil, accessibilityLabel: "Test"
            )
            let whole = StatusItemImage.make(descriptor)
            let rest = StatusItemImage.make(descriptor, drawsMark: false)
            #expect(rest.size == whole.size)
            #expect(rest.isTemplate)
            let drawn = try coverage(of: whole)
            #expect(drawn.contains(true))
            #expect(try !coverage(of: rest).contains(true))

            // A status bar button is flipped and centers its image, as this one does.
            let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: whole.size.width + 16, height: 22))
            button.image = rest
            button.imagePosition = .imageOnly
            let window = NSWindow(contentRect: button.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = button
            defer { window.close() }
            let view = StatusItemMotionView(provider: provider)
            view.install(in: button)
            button.layoutSubtreeIfNeeded()
            #expect(view.frame == NSRect(x: 8, y: 2, width: 18, height: 18))
            #expect(view.hitTest(NSPoint(x: 9, y: 9)) == nil)

            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let moving = try coverage(of: #require(bitmap.cgImage))
            #expect(moving.count == drawn.count)
            let differing = zip(moving, drawn).count { $0 != $1 }
            // Same shape, the same way up, in the same place: only edge pixels may differ.
            #expect(Double(differing) / Double(drawn.count) < 0.04)

            let motion = try #require(view.layer?.sublayers?.first?.animation(forKey: "working") as? CAKeyframeAnimation)
            #expect(motion.duration == WorkingMotion.period)
            #expect(motion.repeatCount == .infinity)
            #expect(motion.preferredFrameRateRange.preferred == Float(WorkingMotion.frameRate))
            #expect(motion.values?.first as! CGPath == ProviderGlyph.path(for: provider, in: view.bounds, phase: 0))
        }
    }

    /// Which pixels of the mark frame are mostly opaque.
    private func coverage(of image: NSImage) throws -> [Bool] {
        try coverage(of: #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

    private func coverage(of image: CGImage) throws -> [Bool] {
        let side = Int(StatusItemImage.markFrame.width) * 2
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ))
        // Draws the leading square of the image, top row first.
        let scale = CGFloat(side) / CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(side)))
        let data = try #require(context.data)
        return (0..<side * side).map { data.load(fromByteOffset: $0, as: UInt8.self) > 127 }
    }
}
