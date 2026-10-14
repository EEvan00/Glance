import XCTest
@testable import GlanceCore

final class FooterLayoutTests: XCTestCase {
    func testDefaultLayoutAndOverflow() {
        var layout = FooterLayout.defaultLayout
        XCTAssertEqual(layout.modules.map(\.kind), [.timer, .weather, .date, .clock, .screenshot])
        XCTAssertEqual(layout.modules.map(\.width), [1, 2, 2, 2, 1])
        XCTAssertEqual(layout.usedSlots, 8)
        XCTAssertFalse(layout.add(FooterModule(kind: .notes)))
    }

    func testMixedWidthMoveResizeAndRemovalPackContinuously() {
        let first = FooterModule(kind: .weather, width: 2)
        let second = FooterModule(kind: .timer)
        let third = FooterModule(kind: .clock, width: 2)
        var layout = FooterLayout(modules: [first, second, third])
        XCTAssertTrue(layout.move(id: third.id, to: 0))
        XCTAssertEqual(layout.startSlot(for: first.id), 2)
        XCTAssertTrue(layout.resize(id: third.id, width: 1))
        XCTAssertEqual(layout.startSlot(for: first.id), 1)
        XCTAssertTrue(layout.remove(id: first.id))
        XCTAssertEqual(layout.startSlot(for: second.id), 1)
        XCTAssertEqual(layout.remainingSlots, 6)
        XCTAssertFalse(layout.resize(id: third.id, width: 3))
    }

    func testDuplicatesAndCustomTargetsRemainIndependent() {
        let first = FooterModule(kind: .application, title: "A", target: "/A.app")
        let second = FooterModule(kind: .application, title: "B", target: "/B.app")
        var layout = FooterLayout(modules: [first, second])
        XCTAssertTrue(layout.add(FooterModule(kind: .timer)))
        XCTAssertFalse(layout.add(FooterModule(kind: .timer)))
        XCTAssertFalse(layout.add(first))
        var changed = first
        changed.target = "/Changed.app"
        XCTAssertTrue(layout.update(changed))
        XCTAssertEqual(layout.modules[1].target, "/B.app")
        XCTAssertTrue(layout.remove(id: first.id))
        XCTAssertEqual(layout.modules.first, second)
    }

    func testSanitizationRetainsOrderedValidRecords() throws {
        let data = Data("""
        {"version":1,"modules":[
        {"id":"\(UUID())","kind":"weather","width":2,"title":"","target":""},
        {"id":"\(UUID())","kind":"future","width":1},
        {"id":"\(UUID())","kind":"weather","width":1},
        {"id":"\(UUID())","kind":"date","width":3},
        {"id":"\(UUID())","kind":"timer","width":1},
        {"id":"\(UUID())","kind":"clock","width":2}]}
        """.utf8)
        let layout = try JSONDecoder().decode(FooterLayout.self, from: data)
        XCTAssertEqual(layout.modules.map(\.kind), [.weather, .timer, .clock])
        XCTAssertEqual(layout.usedSlots, 5)
    }

    func testInsertionOverflowAndInvalidOperationsAreAtomic() {
        let first = FooterModule(kind: .weather, width: 2)
        let second = FooterModule(kind: .clock, width: 2)
        var layout = FooterLayout(modules: [first, second])
        let timer = FooterModule(kind: .timer)
        XCTAssertTrue(layout.add(timer, at: 1))
        XCTAssertEqual(layout.modules.map(\.kind), [.weather, .timer, .clock])
        XCTAssertTrue(layout.add(FooterModule(kind: .date, width: 2)))
        XCTAssertTrue(layout.resize(id: timer.id, width: 2))
        let full = layout
        XCTAssertFalse(layout.add(FooterModule(kind: .notes)))
        XCTAssertFalse(layout.move(id: timer.id, to: -1))
        XCTAssertFalse(layout.remove(id: UUID()))
        XCTAssertFalse(layout.update(FooterModule(kind: .notes)))
        XCTAssertEqual(layout, full)
        XCTAssertTrue(layout.move(id: first.id, to: layout.modules.count))
        XCTAssertEqual(layout.modules.last?.id, first.id)
    }

    func testDecodeDropsOverCapacityAndDuplicateIDsThenPreservesLaterFit() throws {
        let duplicate = FooterModule(kind: .application, width: 2, target: "A")
        let records = [duplicate, duplicate,
                       FooterModule(kind: .weather, width: 2), FooterModule(kind: .clock, width: 2),
                       FooterModule(kind: .timer), FooterModule(kind: .date, width: 2),
                       FooterModule(kind: .notes)]
        let encoded = try JSONEncoder().encode(records)
        let envelope = Data("{\"version\":1,\"modules\":".utf8) + encoded + Data("}".utf8)
        let layout = try JSONDecoder().decode(FooterLayout.self, from: envelope)
        XCTAssertEqual(layout.modules.map(\.kind), [.application, .weather, .clock, .timer, .notes])
        XCTAssertEqual(layout.usedSlots, 8)
        XCTAssertEqual(try JSONDecoder().decode(FooterLayout.self, from: JSONEncoder().encode(layout)), layout)
        XCTAssertThrowsError(try JSONDecoder().decode(FooterLayout.self, from: Data("{\"version\":99,\"modules\":[]}".utf8)))
    }

    @MainActor
    func testPersistedInstancesAndFooterUtilitiesRemainIndependent() throws {
        let name = "FooterLayoutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let a = FooterModule(kind: .shortcut, title: "A", target: "First")
        let b = FooterModule(kind: .shortcut, title: "B", target: "Second")
        store.footerLayout = FooterLayout(modules: [a, b, FooterModule(kind: .codex)])
        XCTAssertTrue(store.visiblePopupUtilities.contains(.codex))
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.footerLayout, store.footerLayout)
        XCTAssertTrue(restored.footerLayout.remove(id: a.id))
        XCTAssertEqual(restored.footerLayout.modules.first, b)
        defaults.set("notes", forKey: "firstQuickAction")
        XCTAssertEqual(SettingsStore(defaults: defaults).footerLayout.modules.first, b)
    }

    @MainActor
    func testLegacyMigrationAndEmptyRestart() throws {
        let name = "FooterLayoutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("application", forKey: "firstQuickAction")
        defaults.set("shortcut", forKey: "secondQuickAction")
        defaults.set("/Applications/Example.app", forKey: "quickActionApplicationPath")
        defaults.set("Example Shortcut", forKey: "quickActionShortcutName")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.footerLayout.modules.first?.target, "/Applications/Example.app")
        XCTAssertEqual(store.footerLayout.modules.last?.target, "Example Shortcut")
        XCTAssertNotNil(defaults.data(forKey: SettingsStore.footerLayoutDefaultsKey))
        store.footerLayout = FooterLayout(modules: [])
        XCTAssertTrue(SettingsStore(defaults: defaults).footerLayout.modules.isEmpty)
        defaults.set(Data("invalid".utf8), forKey: SettingsStore.footerLayoutDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).footerLayout.modules.map(\.kind), FooterLayout.defaultLayout.modules.map(\.kind))
    }
}
