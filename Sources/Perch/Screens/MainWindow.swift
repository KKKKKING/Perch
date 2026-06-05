import AppKit

/// Main app window. Repositions the native traffic lights so the close/min/zoom
/// group is horizontally centered within the rail, with the top margin equal to
/// the side margin. Runs on every layout pass to survive fullscreen transitions.
final class MainWindow: NSWindow {
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard let close = standardWindowButton(.closeButton),
              let mini = standardWindowButton(.miniaturizeButton),
              let zoom = standardWindowButton(.zoomButton),
              let bar = close.superview else { return }

        let bh = close.frame.height
        let spacing = mini.frame.minX - close.frame.minX
        let groupW = close.frame.width + 2 * spacing
        let inset = (UI.railW - groupW) / 2
        let y = bar.bounds.height - bh - inset

        close.setFrameOrigin(NSPoint(x: inset, y: y))
        mini.setFrameOrigin(NSPoint(x: inset + spacing, y: y))
        zoom.setFrameOrigin(NSPoint(x: inset + 2 * spacing, y: y))
    }
}
