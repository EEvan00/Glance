import AppKit
import XCTest
@testable import GlanceCore

@MainActor
final class MediaProgressStyleTests: XCTestCase {
    func testWhiteFillChangesPixelsWhileNativeUnfilledTrackStaysUnchanged() throws {
        let original = NSSlider(frame: NSRect(x: 0, y: 0, width: 280, height: 12))
        let updated = MediaProgressControl(frame: original.frame)
        updated.cell = MediaProgressCell()
        for slider in [original, updated] {
            slider.appearance = NSAppearance(named: .darkAqua)
            slider.controlSize = .mini
            slider.minValue = 0; slider.maxValue = 1; slider.doubleValue = 0.65
        }
        let before = try render(original)
        let after = try render(updated)
        let output = URL(fileURLWithPath: "/tmp/glance-media-progress-after.png")
        try after.representation(using: .png, properties: [:])?.write(to: output)
        var fillChanged = 0, unfilledChanged = 0
        for y in 0..<before.pixelsHigh {
            for x in 0..<before.pixelsWide {
                let a = try XCTUnwrap(before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let change = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
                if change > 0.05 {
                    if x < before.pixelsWide / 2 { fillChanged += 1 }
                    if x > before.pixelsWide * 4 / 5 { unfilledChanged += 1 }
                }
            }
        }
        XCTAssertGreaterThan(fillChanged, 20, "The filled portion must visibly change")
        XCTAssertEqual(unfilledChanged, 0, "The native unfilled track must be unchanged")
    }

    private func render(_ slider: NSSlider) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(slider.bitmapImageRepForCachingDisplay(in: slider.bounds))
        slider.appearance?.performAsCurrentDrawingAppearance {
            slider.cacheDisplay(in: slider.bounds, to: image)
        }
        return image
    }
}
