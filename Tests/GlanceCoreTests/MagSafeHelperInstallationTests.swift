import XCTest
@testable import MagSafeSMC

final class MagSafeHelperInstallationTests: XCTestCase {
    func testRejectsAnUnsignedApplicationEvenWithMatchingBuild() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        let installation = MagSafeHelperInstallation(build: "10", requirement: "identifier io.github.EEvan00.Glance")
        XCTAssertNil(MagSafeHelperInstallation.requirement(for: app))
        XCTAssertFalse(installation.matches(app: app, build: "10"))
    }

    func testAdHocApplicationProducesAnEffectiveRequirement() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let contents = app.appendingPathComponent("Contents")
        let binaries = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: binaries.appendingPathComponent("Probe").path)
        let info: [String: String] = ["CFBundleExecutable": "Probe", "CFBundleIdentifier": "io.github.EEvan00.Glance.SignatureTest", "CFBundleVersion": "10", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", app.path]
        signer.standardOutput = FileHandle.nullDevice
        signer.standardError = FileHandle.nullDevice
        try signer.run()
        signer.waitUntilExit()
        XCTAssertEqual(signer.terminationStatus, 0)
        let requirement = try XCTUnwrap(MagSafeHelperInstallation.requirement(for: app))
        XCTAssertFalse(requirement.isEmpty)
        let installation = MagSafeHelperInstallation(build: "10", requirement: requirement)
        XCTAssertTrue(installation.matches(app: app, build: "10"))
    }

    func testRejectsAnInstallationFromAnotherBuild() {
        let installation = MagSafeHelperInstallation(build: "9", requirement: "identifier io.github.EEvan00.Glance")
        XCTAssertFalse(installation.matches(app: URL(fileURLWithPath: "/Applications/Glance.app"), build: "10"))
    }
}
