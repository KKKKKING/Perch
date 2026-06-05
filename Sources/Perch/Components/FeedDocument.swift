import AppKit

/// A flipped scroll document that stacks an ordered list of rows top-to-bottom.
/// Rows whose height changes after layout (folded text expanding, an image
/// resolving its real aspect ratio) call back into `restack()`, which re-flows
/// everything below and resizes the document so the scroll view picks it up.
final class FeedDocument: FlippedView {
    private(set) var rows: [NSView] = []
    private let topInset: CGFloat
    private let bottomPad: CGFloat
    private let docWidth: CGFloat

    init(width: CGFloat, topInset: CGFloat = 0, bottomPad: CGFloat = 24) {
        self.docWidth = width
        self.topInset = topInset
        self.bottomPad = bottomPad
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: topInset + bottomPad))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Append a row (its current x is preserved; y is assigned by `restack`).
    func append(_ view: NSView) {
        rows.append(view)
        addSubview(view)
    }

    /// Re-assign each row's y from its current height, then resize self.
    func restack() {
        var y = topInset
        for r in rows {
            r.frame.origin.y = y
            y += r.frame.height
        }
        frame = NSRect(x: 0, y: 0, width: docWidth, height: ceil(y + bottomPad))
    }
}

/// A document whose whole body is produced by a closure that can be re-run in
/// place (used by the detail screen when a dynamic image resolves its height).
final class RebuildableDocument: FlippedView {
    var rebuild: (() -> Void)?
}
