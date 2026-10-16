import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class PopupProgressBarTests: XCTestCase {
    func testEmptyQuotaTrackUsesTheSameGrayAsVolumeInLightMode() throws {
        XCTAssertEqual(try trackBrightness(.light), 0.88, accuracy: 0.02)
    }

    func testDarkQuotaTrackRetainsItsExistingContrast() throws {
        XCTAssertEqual(try trackBrightness(.dark), 0.18, accuracy: 0.02)
    }

    private func trackBrightness(_ scheme: ColorScheme) throws -> Double {
        let renderer = ImageRenderer(content: PopupProgressBar(percent: 0)
            .frame(width: 100)
            .background(scheme == .light ? Color.white : Color.black)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let offset = ((image.height / 2) * image.width + image.width / 2) * 4
            let bytes = buffer.bindMemory(to: UInt8.self)
            return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / (3 * 255)
        }
    }
}
