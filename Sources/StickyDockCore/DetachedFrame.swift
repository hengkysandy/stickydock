import Foundation

/// A rectangle in screen coordinates, kept free of AppKit so it can be tested.
public struct NoteFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

public struct NotePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Geometry for notes that have been dragged out of the dock onto the desktop.
public enum DetachedFrame {
    public static let defaultSize = NoteFrame(x: 0, y: 0, width: 260, height: 220)
    public static let minimumSize = (width: 140.0, height: 100.0)

    public static func defaultFrame(around point: NotePoint) -> NoteFrame {
        NoteFrame(
            x: point.x - defaultSize.width / 2,
            y: point.y - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }

    /// Keeps a saved window frame reachable.
    ///
    /// Screens come and go. A note parked on a second monitor would otherwise be
    /// restored at coordinates that no longer exist on any display, leaving the
    /// user with a note they cannot see and cannot close. If the frame still
    /// overlaps a screen it is left exactly where it is; only a stranded one is
    /// moved.
    public static func clamp(_ frame: NoteFrame, toAnyOf screens: [NoteFrame]) -> NoteFrame {
        guard !screens.isEmpty else { return frame }

        var result = frame
        result.width = max(result.width, minimumSize.width)
        result.height = max(result.height, minimumSize.height)

        // Already visible somewhere? Leave it be.
        if let host = screens.first(where: { overlaps(result, $0) }),
           fits(result, in: host) {
            return result
        }

        let target = screens.first(where: { overlaps(result, $0) }) ?? screens[0]
        result.width = min(result.width, target.width)
        result.height = min(result.height, target.height)
        result.x = min(max(result.x, target.x), target.maxX - result.width)
        result.y = min(max(result.y, target.y), target.maxY - result.height)
        return result
    }

    private static func overlaps(_ a: NoteFrame, _ b: NoteFrame) -> Bool {
        a.x < b.maxX && a.maxX > b.x && a.y < b.maxY && a.maxY > b.y
    }

    private static func fits(_ frame: NoteFrame, in screen: NoteFrame) -> Bool {
        frame.x >= screen.x && frame.y >= screen.y
            && frame.maxX <= screen.maxX && frame.maxY <= screen.maxY
    }
}
