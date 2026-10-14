import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class FooterRenderingTests: XCTestCase {
    func testSlotMenuHasVisibleClickableControlAndAddsSelectedModule() throws {
        var layout = FooterLayout(modules: [])
        let host = NSHostingView(rootView: FooterSlotMenu(
            groups: [.init(title: "Information", items: [
                .init(kind: .date, title: "Date", enabled: true),
                .init(kind: .clock, title: "Clock", enabled: false)
            ])], label: "Add", targeted: false,
            select: { _ = layout.add(FooterModule(kind: $0, width: 1)) })
            .frame(width: 24, height: 24))
        host.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        host.layoutSubtreeIfNeeded()
        func findButton(_ view: NSView) -> FooterSlotMenu.SlotButton? {
            if let button = view as? FooterSlotMenu.SlotButton { return button }
            return view.subviews.lazy.compactMap { findButton($0) }.first
        }
        let button = try XCTUnwrap(findButton(host))
        XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
        var ancestor: NSView? = button
        while let view = ancestor {
            XCTAssertGreaterThan(view.alphaValue, 0)
            ancestor = view.superview
        }
        XCTAssertEqual(button.bounds.width, 24, accuracy: 0.5)
        XCTAssertEqual(button.bounds.height, 24, accuracy: 0.5)
        for point in [NSPoint(x: 1, y: 1), NSPoint(x: 12, y: 12), NSPoint(x: 23, y: 23)] {
            XCTAssertNotNil(button.hitTest(button.convert(point, to: button.superview)))
        }
        let menu = try XCTUnwrap(button.menu?.items.last?.submenu)
        XCTAssertEqual(menu.items.map(\.title), ["Date", "Clock"])
        XCTAssertNil(menu.items.first?.submenu)
        XCTAssertFalse(menu.items[1].isEnabled)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(layout.modules.first?.kind, .date)
        XCTAssertEqual(layout.usedSlots, 1)
    }

    func testCatalogNamesAreStandaloneLabelsInEveryLanguage() {
        let localization = Localization(preferredLanguages: ["en"])
        for language in AppLanguage.allCases {
            for kind in FooterModuleKind.allCases {
                let label = localization.string(kind.labelKey, language: language)
                XCTAssertFalse(label.contains("%"), "Unformatted catalog label: \(kind) / \(language): \(label)")
            }
        }
    }

    func testFooterKeepsFixedWidthAcrossEmptyPartialAndFullLayouts() {
        let localization = Localization(preferredLanguages: ["en"])
        let layouts = [FooterLayout(modules: []), FooterLayout(modules: [FooterModule(kind: .weather, width: 2)]), .defaultLayout]
        for layout in layouts {
            let content = FooterModulesView(layout: layout,
                content: { FooterTileContent(symbol: $0.kind.symbol, text: "12:00", help: "Example") },
                activate: { _ in }, openSettings: {}, quit: {})
                .environmentObject(localization)
            let host = NSHostingView(rootView: content)
            XCTAssertEqual(host.fittingSize.width, 276, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, 24, accuracy: 0.5)
        }
    }

    func testEditorFitsSettingsWindowAndCanRenderForReview() throws {
        let name = "GlanceCoreTests.FooterRendering.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
        let host = NSHostingView(rootView: FooterModulesSettingsPane(store: settings)
            .environmentObject(localization).environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = NSRect(x: 0, y: 0, width: 450, height: 480)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 450, accuracy: 0.5)
        if let output = ProcessInfo.processInfo.environment["GLANCE_RENDER_ARTIFACTS"] {
            for (filename, layout) in [("footer-settings", settings.footerLayout), ("footer-settings-empty", FooterLayout(modules: []))] {
                settings.footerLayout = layout
                host.rootView = FooterModulesSettingsPane(store: settings)
                    .environmentObject(localization).environment(\.colorScheme, .light)
                    .background(Color(nsColor: .windowBackgroundColor))
                host.layoutSubtreeIfNeeded()
                let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: image)
                let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename + ".png"))
            }
        }
    }
}
