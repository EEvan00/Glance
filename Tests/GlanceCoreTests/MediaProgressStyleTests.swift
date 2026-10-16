import AppKit
import XCTest
@testable import GlanceCore

@MainActor
final class MediaProgressStyleTests: XCTestCase {
    func testNativeKnobGeometryIsPreservedInBothAppearances() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let original = NSSlider(frame: NSRect(x: 0, y: 0, width: 280, height: 12))
            original.cell = NSSliderCell()
            let updated = MediaProgressControl(frame: original.frame)
            updated.cell = MediaProgressCell()
            for slider in [original, updated] {
                slider.appearance = NSAppearance(named: appearance)
                slider.controlSize = .mini
                slider.minValue = 0
                slider.maxValue = 1
                slider.frame = NSRect(x: 0, y: 0, width: 280, height: 17)
            }
            for value in [0.0, 0.5, 1.0] {
                original.doubleValue = value
                updated.doubleValue = value
                for slider in [original, updated] {
                    let image = try XCTUnwrap(slider.bitmapImageRepForCachingDisplay(in: slider.bounds))
                    slider.cacheDisplay(in: slider.bounds, to: image)
                }
                let nativeCell = try XCTUnwrap(original.cell as? NSSliderCell)
                let sharedCell = try XCTUnwrap(updated.cell as? NSSliderCell)
                XCTAssertEqual(nativeCell.knobRect(flipped: original.isFlipped), sharedCell.knobRect(flipped: updated.isFlipped))
                XCTAssertEqual(nativeCell.barRect(flipped: original.isFlipped), sharedCell.barRect(flipped: updated.isFlipped))
            }
        }
    }
}
