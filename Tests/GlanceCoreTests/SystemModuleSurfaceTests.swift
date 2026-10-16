import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class SystemModuleSurfaceTests: XCTestCase {
    func testLightModuleHasAVisibleGrayBorderAroundItsSurface() throws {
        let renderer = ImageRenderer(content: Color.clear
            .frame(width: 100, height: 40)
            .systemModuleSurface()
            .padding(8)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            func brightness(_ y: Int) -> Double {
                let offset = (y * image.width + image.width / 2) * 4
                return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / (3 * 255)
            }
            let interior = brightness(image.height / 2)
            let lightestEdge = max(brightness(16), brightness(image.height - 17))
            XCTAssertLessThan(lightestEdge, interior - 0.01,
                "Both module edges should use gray ink against the light surface")
        }
    }
}
