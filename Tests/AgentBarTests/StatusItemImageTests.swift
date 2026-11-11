@testable import AgentBar
import AgentBarCore
import AppKit
import Testing

@MainActor
struct StatusItemImageTests {
    @Test func restingItemsAreTheSamePictureDrawnFainter() throws {
        _ = NSApplication.shared
        for provider in [ProviderKind.claude, .codex, nil] {
            let resting = image(provider: provider, workingCount: 0)
            let working = image(provider: provider, workingCount: 2)
            #expect(resting.isTemplate)
            // A count only adds to the trailing edge.
            #expect(working.size.width > resting.size.width)
            let faint = try alpha(of: resting, width: resting.size.width)
            let full = try alpha(of: working, width: resting.size.width)
            #expect(faint.count == full.count)
            #expect(full.contains { $0 > 0 })
            let opacity = Double(StatusItemImage.restingOpacity)
            #expect(zip(faint, full).allSatisfy { abs(Double($0) - Double($1) * opacity) <= 1.5 })
        }
    }

    private func image(provider: ProviderKind?, workingCount: Int) -> NSImage {
        StatusItemImage.make(StatusItemDescriptor(
            id: .overview, provider: provider, name: "work", workingCount: workingCount, accessibilityLabel: "Test"
        ))
    }

    /// The alpha of every pixel in the leading `width` points of `image`.
    private func alpha(of image: NSImage, width: CGFloat) throws -> [UInt8] {
        let source = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let columns = Int((width * CGFloat(source.height) / image.size.height).rounded())
        let context = try #require(CGContext(
            data: nil, width: columns, height: source.height, bitsPerComponent: 8, bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let data = try #require(context.data)
        return (0..<columns * source.height).map { data.load(fromByteOffset: $0, as: UInt8.self) }
    }
}
