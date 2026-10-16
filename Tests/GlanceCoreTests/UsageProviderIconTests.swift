import AppKit
import SwiftUI
import XCTest
@testable import GlanceCore

@MainActor
final class UsageProviderIconTests: XCTestCase {
    func testProviderMarksStayVisibleInLightAndDarkAppearances() throws {
        for (provider, name) in [(UsageProviderIcon.Provider.codex, "codex"), (.claude, "claude")] {
            for (scheme, appearance) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                let renderer = ImageRenderer(content: UsageProviderIcon(provider: provider)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 4
                let image = try XCTUnwrap(renderer.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                let brightness: Double = try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                        width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    let bytes = buffer.bindMemory(to: UInt8.self)
                    var total = 0.0
                    var count = 0
                    for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 200 {
                        total += Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])
                        count += 1
                    }
                    XCTAssertGreaterThan(count, 20, "Missing mark: \(name)/\(appearance)")
                    return count == 0 ? 0 : total / Double(count * 3 * 255)
                }
                if scheme == .light {
                    XCTAssertLessThan(brightness, 0.35, "\(name) must use dark ink in light mode")
                } else {
                    XCTAssertGreaterThan(brightness, 0.65, "\(name) must use light ink in dark mode")
                }
                if let directory = ProcessInfo.processInfo.environment["GLANCE_RENDER_ARTIFACTS"] {
                    let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(appearance).png"))
                }
            }
        }
    }
}
