import Foundation
import Security

public struct MagSafeHelperInstallation: Codable, Equatable, Sendable {
    public static let directory = "/Library/Application Support/GlanceHelper"
    public static let configurationPath = directory + "/installation.json"
    public static let binaryPath = "/Library/PrivilegedHelperTools/io.github.EEvan00.Glance.MagSafeLEDHelper"
    public static let plistPath = "/Library/LaunchDaemons/io.github.EEvan00.Glance.MagSafeLEDHelper.plist"
    public let build: String
    public let requirement: String

    public init(build: String, requirement: String) {
        self.build = build
        self.requirement = requirement
    }

    public static func read() -> Self? {
        let path = configurationPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
              let permissions = attrs[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 16384,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.requirement.isEmpty else { return nil }
        return value
    }

    public static func requirement(for app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)), nil) == errSecSuccess else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    public func matches(app: URL, build: String) -> Bool {
        self.build == build && requirement == Self.requirement(for: app)
    }
}
