import AppKit
import SwiftUI

/// A full-slot native menu button with centered artwork and no indicator padding.
struct FooterSlotMenu: NSViewRepresentable {
    struct Item: Equatable {
        let kind: FooterModuleKind
        let title: String
        let enabled: Bool
    }

    struct Group: Equatable {
        let title: String
        let items: [Item]
    }

    let groups: [Group]
    let label: String
    let targeted: Bool
    let select: (FooterModuleKind) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeNSView(context: Context) -> SlotButton {
        SlotButton(frame: .zero, pullsDown: true)
    }

    func updateNSView(_ button: SlotButton, context: Context) {
        context.coordinator.select = select
        if context.coordinator.groups != groups {
            context.coordinator.groups = groups
            let menu = NSMenu()
            menu.autoenablesItems = false
            // NSPopUpButton's first pull-down item is its label, not a selectable entry.
            menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            for group in groups {
                let category = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for item in group.items {
                    let option = NSMenuItem(title: item.title,
                        action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
                    option.target = context.coordinator
                    option.representedObject = item.kind.rawValue
                    option.isEnabled = item.enabled
                    submenu.addItem(option)
                }
                category.submenu = submenu
                menu.addItem(category)
            }
            button.menu = menu
        }
        button.isBordered = false
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.targeted = targeted
        button.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var groups: [Group]?
        var select: (FooterModuleKind) -> Void
        init(select: @escaping (FooterModuleKind) -> Void) { self.select = select }

        @objc func choose(_ sender: NSMenuItem) {
            guard sender.isEnabled, let value = sender.representedObject as? String,
                  let kind = FooterModuleKind(rawValue: value) else { return }
            select(kind)
        }
    }

    final class SlotButton: NSPopUpButton {
        var targeted = false

        override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }
        override var alignmentRectInsets: NSEdgeInsets {
            NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }

        override func draw(_ dirtyRect: NSRect) {
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: 6, yRadius: 6)
            border.lineWidth = 1
            border.setLineDash([3], count: 1, phase: 0)
            (targeted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.4)).setStroke()
            border.stroke()
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: bounds.midX - 4, y: bounds.midY))
            plus.line(to: NSPoint(x: bounds.midX + 4, y: bounds.midY))
            plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 4))
            plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 4))
            plus.lineWidth = 1
            NSColor.secondaryLabelColor.setStroke()
            plus.stroke()
        }
    }
}
