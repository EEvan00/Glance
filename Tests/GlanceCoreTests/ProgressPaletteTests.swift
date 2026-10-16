import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class ProgressPaletteTests: XCTestCase {
    func testLightModeProgressColorsMatchAcrossQuotaVolumeAndMusic() throws {
        try assertPalette(scheme: .light, fill: 0.986, track: 0.88)
    }

    func testDarkModeProgressColorsMatchAcrossQuotaVolumeAndMusic() throws {
        try assertPalette(scheme: .dark, fill: 0.902, track: 0.18)
    }

    private func assertPalette(scheme: ColorScheme, fill: Double, track: Double) throws {
        let quota = try render(PopupProgressBar(percent: 50), scheme: scheme)
        let volume = try render(CapsuleSlider(value: .constant(0.5), label: "Volume", onChange: { _, _ in }) {
            EmptyView()
        }, scheme: scheme)
        let music = MediaProgressControl(frame: NSRect(x: 0, y: 0, width: 100, height: 12))
        music.cell = MediaProgressCell()
        music.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        music.controlSize = .mini
        music.minValue = 0
        music.maxValue = 1
        music.doubleValue = 0.5
        let bitmap = try XCTUnwrap(music.bitmapImageRepForCachingDisplay(in: music.bounds))
        music.appearance?.performAsCurrentDrawingAppearance {
            music.cacheDisplay(in: music.bounds, to: bitmap)
        }
        for (label, image) in [("Quota", quota), ("Volume", volume), ("Music", bitmap)] {
            XCTAssertEqual(try brightness(image, fraction: 0.25, scheme: scheme), fill, accuracy: 0.035, "\(label) fill")
            XCTAssertEqual(try brightness(image, fraction: 0.8, scheme: scheme), track, accuracy: 0.035, "\(label) track")
        }
    }

    private func render<V: View>(_ content: V, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content.frame(width: 100)
            .background(scheme == .light ? Color.white : Color.black)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func brightness(_ image: NSBitmapImageRep, fraction: Double, scheme: ColorScheme) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.pixelsWide * image.pixelsHigh * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: image.pixelsWide, height: image.pixelsHigh, bitsPerComponent: 8,
                bytesPerRow: image.pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(gray: scheme == .light ? 1 : 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh))
            let offset = ((image.pixelsHigh / 2) * image.pixelsWide + Int(Double(image.pixelsWide) * fraction)) * 4
            let bytes = buffer.bindMemory(to: UInt8.self)
            return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / (3 * 255)
        }
    }
}
