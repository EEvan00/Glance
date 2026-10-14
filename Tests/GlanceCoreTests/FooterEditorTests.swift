import XCTest
@testable import GlanceCore

final class FooterEditorTests: XCTestCase {
    func testDroppingMixedWidthNeighborsOnEachOtherMovesWholeModulesInBothDirections() {
        for widths in [[1, 2], [2, 1]] {
            let a = FooterModule(kind: .timer, width: widths[0])
            let b = FooterModule(kind: .weather, width: widths[1])
            for (source, target) in [(a, b), (b, a)] {
                var layout = FooterLayout(modules: [a, b])
                XCTAssertTrue(FooterEditorDrop.apply("module:\(source.id)", onto: target.id, to: &layout))
                XCTAssertEqual(layout.modules, [b, a])
                XCTAssertEqual(layout.startSlot(for: a.id), b.width)
            }
        }
    }

    func testMovingForwardDropsBeforeTargetAndKeepsWidths() {
        let a = FooterModule(kind: .weather, width: 2)
        let b = FooterModule(kind: .clock, width: 2)
        let c = FooterModule(kind: .screenshot)
        var layout = FooterLayout(modules: [a, b, c])
        XCTAssertTrue(FooterEditorDrop.apply("module:\(a.id)", before: c.id, to: &layout))
        XCTAssertEqual(layout.modules.map(\.id), [b.id, a.id, c.id])
        XCTAssertEqual(layout.usedSlots, 5)
    }

    func testLibraryDropAppendsAndRejectsOverflowWithoutChangingLayout() {
        var layout = FooterLayout.defaultLayout
        let original = layout
        XCTAssertFalse(FooterEditorDrop.apply("kind:calculator", before: nil, to: &layout))
        XCTAssertEqual(layout, original)
        layout = FooterLayout(modules: [])
        XCTAssertTrue(FooterEditorDrop.apply("kind:calculator", before: nil, to: &layout))
        XCTAssertEqual(layout.modules.map(\.kind), [.calculator])
        XCTAssertFalse(FooterEditorDrop.apply("unrelated text", before: nil, to: &layout))
    }
}
