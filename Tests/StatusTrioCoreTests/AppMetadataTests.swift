// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import XCTest
@testable import StatusTrioCore

final class AppMetadataTests: XCTestCase {
    func testNameUsesDisplayNameFirst() {
        let name = AppMetadata.name(from: [
            "CFBundleDisplayName": "Localized Name",
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Localized Name")
    }

    func testNameFallsBackToBundleName() {
        let name = AppMetadata.name(from: [
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Bundle Name")
    }

    func testNameFallsBackToDefault() {
        XCTAssertEqual(AppMetadata.name(from: [:]), "Glance")
    }

    func testProjectHomepageURL() {
        XCTAssertEqual(
            AppMetadata.projectHomepageURL.absoluteString,
            "https://github.com/EEvan00/Glance"
        )
    }

    func testGitHubMarkLoadsFromResourceBundle() {
        XCTAssertNotNil(AboutIcon.githubMark)
    }
}
