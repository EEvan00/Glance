import Foundation
import XCTest
@testable import GlanceCore

@MainActor
final class FooterActionTests: XCTestCase {
    func testWebsiteRejectsNonHTTPAndMissingHost() {
        for target in ["file:///tmp/test", "javascript:alert(1)", "https://", "example.com"] {
            XCTAssertThrowsError(try FooterActionTarget.url(kind: .website, target: target))
        }
        XCTAssertEqual(try FooterActionTarget.url(kind: .website, target: "https://example.com/a?q=1").host, "example.com")
    }

    func testShortcutNameCannotInjectURLParameters() throws {
        let name = "你好 &name=Other/#?"
        let url = try FooterActionTarget.url(kind: .shortcut, target: name)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "run-shortcut")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: name)])
        XCTAssertThrowsError(try FooterActionTarget.url(kind: .shortcut, target: "  "))
    }

    func testFileFolderAndApplicationHaveDistinctValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.txt")
        try Data().write(to: file)
        XCTAssertEqual(try FooterActionTarget.url(kind: .file, target: file.path), file)
        let folderURL = try FooterActionTarget.url(kind: .folder, target: root.path)
        XCTAssertTrue(folderURL.isFileURL)
        XCTAssertEqual(folderURL.standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertThrowsError(try FooterActionTarget.url(kind: .folder, target: file.path))
        XCTAssertThrowsError(try FooterActionTarget.url(kind: .file, target: root.path))
        XCTAssertThrowsError(try FooterActionTarget.url(kind: .application, target: root.path))
        XCTAssertThrowsError(try FooterActionTarget.url(kind: .file, target: "relative.txt"))
    }

    func testKeepAwakeStopsOnceAndDeinitReleases() {
        var releases: [UInt32] = []
        let effects = FooterActionEffects(open: { _ in true }, acquire: { 42 }, release: { releases.append($0); return true })
        var controller: FooterActionController? = FooterActionController(localization: Localization(), effects: effects)
        controller?.perform(FooterModule(kind: .keepAwake, width: 1))
        XCTAssertEqual(controller?.isKeepingAwake, true)
        controller?.stop()
        controller?.stop()
        XCTAssertEqual(releases, [42])
        controller?.perform(FooterModule(kind: .keepAwake, width: 1))
        controller = nil
        XCTAssertEqual(releases, [42, 42])
    }

    func testFailedReleaseKeepsOwnershipForRetry() {
        var allowRelease = false
        var attempts = 0
        let controller = FooterActionController(localization: Localization(), effects: FooterActionEffects(
            open: { _ in true }, acquire: { 7 }, release: { _ in attempts += 1; return allowRelease }))
        controller.perform(FooterModule(kind: .keepAwake))
        controller.stop()
        XCTAssertTrue(controller.isKeepingAwake)
        XCTAssertNotNil(controller.errorMessage)
        allowRelease = true
        controller.stop()
        XCTAssertFalse(controller.isKeepingAwake)
        XCTAssertEqual(attempts, 2)
    }

    func testValidWebsiteDispatchesAndInvalidTargetNeverOpens() {
        var opened: [URL] = []
        let controller = FooterActionController(localization: Localization(), effects: FooterActionEffects(
            open: { opened.append($0); return true }, acquire: { nil }, release: { _ in true }))
        controller.perform(FooterModule(kind: .website, target: "javascript:alert(1)"))
        XCTAssertTrue(opened.isEmpty)
        XCTAssertNotNil(controller.errorMessage)
        controller.perform(FooterModule(kind: .website, target: "https://example.com/path"))
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com/path"])
        XCTAssertNil(controller.errorMessage)
    }

    func testRemovingKeepAwakeModuleReleasesAssertion() {
        var released: [UInt32] = []
        let controller = FooterActionController(localization: Localization(), effects: FooterActionEffects(
            open: { _ in true }, acquire: { 9 }, release: { released.append($0); return true }))
        controller.perform(FooterModule(kind: .keepAwake))
        controller.reconcile(layout: FooterLayout(modules: [FooterModule(kind: .keepAwake)]))
        XCTAssertTrue(controller.isKeepingAwake)
        XCTAssertTrue(released.isEmpty)
        controller.reconcile(layout: FooterLayout(modules: []))
        XCTAssertFalse(controller.isKeepingAwake)
        XCTAssertEqual(released, [9])
        controller.reconcile(layout: .defaultLayout)
        XCTAssertEqual(released, [9])
    }

    func testFailedAcquireAndOpenDoNotClaimSuccess() {
        let controller = FooterActionController(localization: Localization(), effects: FooterActionEffects(open: { _ in false }, acquire: { nil }, release: { _ in true }))
        controller.perform(FooterModule(kind: .keepAwake, width: 1))
        XCTAssertFalse(controller.isKeepingAwake)
        XCTAssertNotNil(controller.errorMessage)
        controller.perform(FooterModule(kind: .website, width: 1, target: "https://example.com"))
        XCTAssertNotNil(controller.errorMessage)
    }
}
