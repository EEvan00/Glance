// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import AppKit

/// A menu-bar panel without NSPopover's system-drawn arrow.
@MainActor
final class StatusPopupPanel: NSPanel, NSWindowDelegate {
    static let cornerRadius: CGFloat = 12
    var onClose: (() -> Void)?
    var preventsAutomaticDismissal: (() -> Bool)?
    private var sizeObservation: NSKeyValueObservation?
    private var anchor = NSRect.zero
    private var screenFrame = NSRect.zero
    private var menuBarBottom: CGFloat = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .fullScreenAuxiliary]
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var isShown: Bool { isVisible }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        guard let window = view.window, let controller = contentViewController else { return }
        anchor = window.convertToScreen(view.convert(rect, to: nil))
        screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        menuBarBottom = min(window.frame.minY, screenFrame.maxY)
        let content = controller.view
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        resizeToContent()
        sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.resizeToContent()
            }
        }
        orderFront(nil)
    }

    private func resizeToContent() {
        guard let controller = contentViewController else { return }
        var size = controller.preferredContentSize
        if size.width <= 0 || size.height <= 0 { size = controller.view.fittingSize }
        guard size.width > 0, size.height > 0 else { return }
        setFrame(Self.frame(for: size, anchor: anchor, screenFrame: screenFrame, menuBarBottom: menuBarBottom), display: true)
    }

    static func frame(for requestedSize: NSSize, anchor: NSRect, screenFrame: NSRect, menuBarBottom: CGFloat) -> NSRect {
        let top = min(anchor.minY, menuBarBottom, screenFrame.maxY)
        let size = NSSize(width: min(requestedSize.width, screenFrame.width),
                          height: min(requestedSize.height, max(0, top - screenFrame.minY)))
        let x = max(screenFrame.minX, min(anchor.midX - size.width / 2, screenFrame.maxX - size.width))
        let y = max(screenFrame.minY, top - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    override func performClose(_ sender: Any?) {
        guard isVisible else { return }
        sizeObservation = nil
        orderOut(sender)
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    func windowDidResignKey(_ notification: Notification) {
        dismissAutomatically()
    }

    func dismissAutomatically() {
        // Sheets and system credential prompts temporarily take keyboard focus.
        guard attachedSheet == nil, preventsAutomaticDismissal?() != true else { return }
        performClose(nil)
    }
}
