import AppKit

/// Borderless, movable, key-capable window that hosts an auxiliary panel
/// (compose / settings / add-account) as a real independent window.
/// Borderless lets the rounded card define the window shape while still being
/// a top-level `NSWindow` — movable anywhere, listed in the Window menu, and
/// independent of the main window.
final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// How a panel's host window is chromed.
enum PanelStyle {
    case card    // borderless floating card (the panel draws its own rounded chrome)
    case window  // standard titled window (traffic lights + title bar)
}

/// A view hosted inside a `PanelWindowController`.
protocol PanelContentView: NSView {
    /// Natural content size of the panel at creation time.
    var panelPreferredSize: CGSize { get }
    /// Title used for the Window menu entry.
    var panelTitle: String { get }
    /// Called once after the window is built so the content can drive resizing.
    func attach(to panel: PanelWindowController)
    /// When true, the host window supports edge/corner drag-resize.
    var panelResizable: Bool { get }
    /// Smallest content size the window may be resized to (when resizable).
    var panelMinSize: CGSize { get }
    /// Chrome style for the host window.
    var panelStyle: PanelStyle { get }
}

extension PanelContentView {
    var panelResizable: Bool { false }
    var panelMinSize: CGSize { CGSize(width: 360, height: 280) }
    var panelStyle: PanelStyle { .card }
}

final class PanelWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var dismissing = false

    init(content: PanelContentView, relativeTo parent: NSWindow?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let size = content.panelPreferredSize
        let titled = content.panelStyle == .window
        var mask: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable] : .borderless
        if content.panelResizable { mask.insert(.resizable) }
        let win = PanelWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: mask,
                              backing: .buffered, defer: false)
        if titled {
            win.isOpaque = true
            win.backgroundColor = ThemeManager.shared.theme.bgElevated
            win.isMovableByWindowBackground = false
            win.titlebarAppearsTransparent = false
        } else {
            win.isOpaque = false
            win.backgroundColor = .clear
            win.isMovableByWindowBackground = true
        }
        win.hasShadow = true
        win.title = content.panelTitle
        win.isExcludedFromWindowsMenu = false
        win.animationBehavior = .documentWindow
        win.contentView = content
        win.setContentSize(size)
        if content.panelResizable {
            win.minSize = content.panelMinSize
            win.contentMinSize = content.panelMinSize
        }
        super.init(window: win)
        win.delegate = self
        content.attach(to: self)
        position(over: parent, size: size)
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Resize so content height matches `height`, keeping the top edge fixed.
    /// Accounts for a title bar when the window is titled (content vs frame height).
    func setContentHeight(_ height: CGFloat) {
        guard let win = window else { return }
        let contentW = win.contentView?.frame.width ?? win.frame.width
        let frameH = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentW, height: height)).height
        if abs(win.frame.height - frameH) < 0.5 { return }
        let top = win.frame.maxY
        var f = win.frame
        f.size.height = frameH
        f.origin.y = top - frameH
        // keep on-screen vertically when growing downward
        if let vis = win.screen?.visibleFrame, f.minY < vis.minY {
            f.origin.y = vis.minY
        }
        win.setFrame(f, display: true)
    }

    /// Close the window programmatically without firing `onClose` back into AppState.
    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        window?.close()
    }

    private func position(over parent: NSWindow?, size: CGSize) {
        guard let win = window else { return }
        guard let parent = parent else { win.center(); return }
        let pf = parent.frame
        let x = pf.minX + (pf.width - size.width) / 2
        let y = pf.minY + (pf.height - size.height) / 2 + pf.height * 0.05
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowWillClose(_ notification: Notification) {
        guard !dismissing else { return }
        onClose()
    }
}
