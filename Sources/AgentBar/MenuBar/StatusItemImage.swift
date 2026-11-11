import AppKit

@MainActor
enum StatusItemImage {
    /// Where the mark is drawn, at the leading edge of every image.
    static let markFrame = CGRect(x: 0, y: 0, width: 18, height: 18)
    /// How strongly an item is drawn while none of its sessions is working.
    static let restingOpacity: CGFloat = 0.6

    /// `drawsMark` is false for an item whose mark moves: `StatusItemMotionView` draws it there instead.
    static func make(_ descriptor: StatusItemDescriptor, drawsMark: Bool = true) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 12)
        // A template image keeps its alpha, so the menu bar shows a resting item fainter.
        let color = NSColor.black.withAlphaComponent(descriptor.workingCount > 0 ? 1 : restingOpacity)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let name = descriptor.displayedName ?? ""
        let nameWidth = name.isEmpty ? 0 : ceil((name as NSString).size(withAttributes: attributes).width) + 5
        let count = descriptor.workingCount > 0 ? String(descriptor.workingCount) : ""
        let countWidth = count.isEmpty ? 0 : ceil((count as NSString).size(withAttributes: attributes).width) + 5
        let size = NSSize(width: markFrame.width + nameWidth + countWidth, height: markFrame.height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        if drawsMark, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            // The glyph is laid out from the top left; this context starts at the bottom left.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(color.cgColor)
            context.addPath(ProviderGlyph.path(for: descriptor.provider, in: markFrame))
            context.fillPath()
            context.restoreGState()
        }
        var x = markFrame.width
        if !name.isEmpty {
            (name as NSString).draw(at: NSPoint(x: x + 2, y: 1), withAttributes: attributes)
            x += nameWidth
        }
        if !count.isEmpty { (count as NSString).draw(at: NSPoint(x: x + 5, y: 1), withAttributes: attributes) }
        image.isTemplate = true
        return image
    }
}
