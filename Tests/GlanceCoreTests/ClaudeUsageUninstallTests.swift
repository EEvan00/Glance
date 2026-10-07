import Foundation
import XCTest
@testable import GlanceCore

final class ClaudeUsageUninstallTests: XCTestCase {
    func testUninstallRestoresOriginalStatusLineAndPreservesNewSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let settings = home.appendingPathComponent(".claude/settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"echo original"},"theme":"old"}"#.utf8).write(to: settings)
        try ClaudeUsageIntegration.install(home: home, support: support)
        var current = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        current["theme"] = "new"
        try JSONSerialization.data(withJSONObject: current).write(to: settings)
        try ClaudeUsageIntegration.uninstall(home: home, support: support)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual((restored["statusLine"] as? [String: Any])?["command"] as? String, "echo original")
        XCTAssertEqual(restored["theme"] as? String, "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
    }

    func testUninstallDoesNotOverwriteUserReplacementStatusLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try ClaudeUsageIntegration.install(home: home, support: support)
        let settings = home.appendingPathComponent(".claude/settings.json")
        let replacement = Data(#"{"statusLine":{"type":"command","command":"echo user"}}"#.utf8)
        try replacement.write(to: settings)
        try ClaudeUsageIntegration.uninstall(home: home, support: support)
        XCTAssertEqual(try Data(contentsOf: settings), replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
    }

    func testMissingBackupKeepsReferencedScriptAndFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try ClaudeUsageIntegration.install(home: home, support: support)
        try FileManager.default.removeItem(at: support.appendingPathComponent("claude-statusline-original.json"))
        XCTAssertThrowsError(try ClaudeUsageIntegration.uninstall(home: home, support: support))
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("claude-statusline.pl").path))
    }
}
