@testable import AgentBar
import CoreGraphics
import Testing

struct ListReorderTests {
    /// Rows 40, 60, 40, and 50 points tall, one under the other: their centers are at 20, 70, 120,
    /// and 165.
    private let frames = [40.0, 60, 40, 50].reduce(into: [CGRect]()) { frames, height in
        frames.append(CGRect(x: 0, y: frames.last?.maxY ?? 0, width: 100, height: height))
    }

    @Test func rowKeepsItsPlaceUntilItsCenterPassesTheCenterOfAnother() throws {
        let held = try #require(ListReorder(frames: frames, source: 1, top: 60))
        #expect(held.destination == 1)
        #expect((0..<4).map(held.offset(of:)) == [0, 20, 0, 0])
        #expect((0..<4).map(held.position(of:)) == [0, 1, 2, 3])
        #expect(held.apply(to: ["a", "b", "c", "d"]) == ["a", "b", "c", "d"])
    }

    @Test func rowsPassedOnTheWayDownMoveUp() throws {
        let down = try #require(ListReorder(frames: frames, source: 0, top: 105))
        #expect(down.destination == 2)
        #expect((0..<4).map(down.offset(of:)) == [105, -40, -40, 0])
        #expect((0..<4).map(down.position(of:)) == [2, 0, 1, 3])
        #expect(down.apply(to: ["a", "b", "c", "d"]) == ["b", "c", "a", "d"])
    }

    @Test func rowsPassedOnTheWayUpMoveDown() throws {
        let up = try #require(ListReorder(frames: frames, source: 3, top: 30))
        #expect(up.destination == 1)
        #expect((0..<4).map(up.offset(of:)) == [0, 50, 50, -110])
        #expect((0..<4).map(up.position(of:)) == [0, 2, 3, 1])
        #expect(up.apply(to: ["a", "b", "c", "d"]) == ["a", "d", "b", "c"])
    }

    @Test func draggedRowStaysWithinTheList() throws {
        let above = try #require(ListReorder(frames: frames, source: 2, top: -500))
        #expect(above.top == 0)
        #expect(above.destination == 0)
        let below = try #require(ListReorder(frames: frames, source: 0, top: 500))
        #expect(below.top == 150)
        #expect(below.destination == 3)
        #expect(ListReorder(frames: frames, source: 4, top: 0) == nil)
        #expect(ListReorder(frames: [], source: 0, top: 0) == nil)
    }

    @Test func rowHeldPastTheEndOfTheListLandsLast() throws {
        let rows = (0..<3).map { CGRect(x: 0, y: CGFloat($0) * 50, width: 100, height: 50) }
        let atLastPlace = try #require(ListReorder(frames: rows, source: 0, top: 100))
        #expect(atLastPlace.destination == 1)
        let past = try #require(ListReorder(frames: rows, source: 0, top: 120))
        #expect(past.top == 100)
        #expect(past.destination == 2)
        #expect(past.apply(to: ["a", "b", "c"]) == ["b", "c", "a"])
    }
}
