import CoreGraphics

/// Where the rows of a list are while one of them is dragged: the dragged row follows the pointer,
/// and the rows between its place and the place it would land in move aside to make room.
struct ListReorder {
    /// The index of the dragged row.
    let source: Int
    /// The index the dragged row lands at if it is dropped now.
    let destination: Int
    /// The top of the dragged row as shown, kept within the list.
    let top: CGFloat
    private let frames: [CGRect]

    /// `frames` are the frames of the rows in their order, each adjoining the next. `top` is where the
    /// pointer holds the top of the row at `source`.
    init?(frames: [CGRect], source: Int, top: CGFloat) {
        guard frames.indices.contains(source), let first = frames.first, let last = frames.last else { return nil }
        let height = frames[source].height
        self.frames = frames
        self.source = source
        self.top = min(max(top, first.minY), last.maxY - height)
        // Where the pointer holds the row, beyond the list too: a row kept within it could not pass
        // the center of a last row of the same height.
        let center = top + height / 2
        destination = frames.indices.filter { $0 != source && frames[$0].midY < center }.count
    }

    /// How far the row at `index` is moved from its place.
    func offset(of index: Int) -> CGFloat {
        if index == source { return top - frames[source].minY }
        if source < index, index <= destination { return -frames[source].height }
        if destination <= index, index < source { return frames[source].height }
        return 0
    }

    /// Where the row at `index` is among the rows as they are shown.
    func position(of index: Int) -> Int {
        if index == source { return destination }
        if source < index, index <= destination { return index - 1 }
        if destination <= index, index < source { return index + 1 }
        return index
    }

    /// `items`, one per row, in the order of the rows as they are shown.
    func apply<Item>(to items: [Item]) -> [Item] {
        var items = items
        items.insert(items.remove(at: source), at: destination)
        return items
    }
}
