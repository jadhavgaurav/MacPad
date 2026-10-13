import AppKit

/// Where each window's tab strip and tabs are on screen, so a tab dragged over another window can be dropped
/// there. Frames use SwiftUI's global space, which is the coordinate space of each window's content view.
@MainActor
final class TabZoneRegistry {
    static let shared = TabZoneRegistry()

    struct Zone {
        weak var window: NSWindow?
        var stripFrame: CGRect = .zero
        var tabFrames: [UUID: CGRect] = [:]
    }

    private(set) var zones: [UUID: Zone] = [:]

    func setWindow(_ window: NSWindow, for id: UUID) {
        zones[id, default: Zone()].window = window
    }

    func updateFrames(for id: UUID, strip: CGRect, tabs: [UUID: CGRect]) {
        zones[id, default: Zone()].stripFrame = strip
        zones[id, default: Zone()].tabFrames = tabs
    }

    func remove(_ id: UUID) {
        zones[id] = nil
    }

    /// The window whose tab strip is under a screen point, with that point in the window's content coordinates.
    func target(atScreenPoint point: NSPoint) -> (window: UUID, local: CGPoint)? {
        for (id, zone) in zones {
            guard let window = zone.window, window.isVisible, let content = window.contentView else { continue }
            let local = content.convert(window.convertPoint(fromScreen: point), from: nil)
            if zone.stripFrame.insetBy(dx: -6, dy: -10).contains(local) { return (id, local) }
        }
        return nil
    }
}
