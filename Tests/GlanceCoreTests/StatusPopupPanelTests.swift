import AppKit
import Testing
@testable import GlanceCore

@MainActor
struct StatusPopupPanelTests {
    @Test func deactivationDoesNotSilentlyHidePanel() {
        let panel = StatusPopupPanel()
        #expect(panel.hidesOnDeactivate == false)
    }

    @Test func outsideMouseDownClosesAndCleansUpOnce() {
        let panel = StatusPopupPanel()
        var closes = 0
        panel.onClose = { closes += 1 }
        panel.setFrame(NSRect(x: 100, y: 100, width: 100, height: 100), display: false)
        panel.orderFront(nil)
        panel.dismissForMouseDown(at: NSPoint(x: 150, y: 150))
        #expect(panel.isVisible)
        panel.dismissForMouseDown(at: NSPoint(x: 250, y: 250))
        panel.dismissForMouseDown(at: NSPoint(x: 250, y: 250))
        #expect(panel.isVisible == false)
        #expect(closes == 1)
    }

    @Test func statusButtonMouseDownLeavesToggleToMouseUp() {
        let panel = StatusPopupPanel()
        let statusWindow = NSWindow(contentRect: NSRect(x: 400, y: 500, width: 40, height: 24),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        statusWindow.contentView = button
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        content.preferredContentSize = NSSize(width: 100, height: 100)
        panel.contentViewController = content
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let anchor = statusWindow.convertToScreen(button.bounds)
        panel.dismissForMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY))
        #expect(panel.isVisible)
        panel.performClose(nil)
    }

    @Test func closingPanelRunsCleanupOnce() {
        let panel = StatusPopupPanel()
        var closes = 0
        panel.onClose = { closes += 1 }
        panel.setFrame(NSRect(x: 0, y: 0, width: 100, height: 100), display: false)
        panel.orderFront(nil)
        panel.performClose(nil)
        panel.performClose(nil)
        #expect(panel.isVisible == false)
        #expect(closes == 1)
    }

    @Test func attachedPasswordSheetDoesNotDismissParent() {
        let panel = StatusPopupPanel()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        panel.setFrame(NSRect(x: 0, y: 0, width: 200, height: 200), display: false)
        panel.orderFront(nil)
        panel.beginSheet(sheet)
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(panel.isVisible)
        panel.endSheet(sheet)
        sheet.orderOut(nil)
        panel.performClose(nil)
    }

    @Test func escapeClosesPanel() {
        let panel = StatusPopupPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 100, height: 100), display: false)
        panel.orderFront(nil)
        panel.cancelOperation(nil)
        #expect(panel.isVisible == false)
    }
}
