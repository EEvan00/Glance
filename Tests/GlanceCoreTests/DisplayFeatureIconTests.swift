import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class DisplayFeatureIconTests: XCTestCase {
    func testEnabledDisplayFeaturesUseBlueAndWhiteInBothAppearances() throws {
        for symbol in ["circle.lefthalf.filled", "sun.max", "sun.max.fill"] {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: DisplayFeatureIcon(symbol: symbol, isOn: true)
                    .accentColor(.purple)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                        width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    let bytes = buffer.bindMemory(to: UInt8.self)
                    var white = 0
                    var blue = 0
                    for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 240 {
                        let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                        if min(r, min(g, b)) > 235 { white += 1 }
                        if b - r > 75 && b - g > 35 { blue += 1 }
                    }
                    XCTAssertGreaterThan(white, 30, "\(symbol)/\(scheme) must have a white enabled glyph")
                    XCTAssertGreaterThan(blue, 100, "\(symbol)/\(scheme) must have a blue enabled background, regardless of accent")
                }
            }
        }
    }
}
