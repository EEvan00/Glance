// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import Foundation

public enum MagSafeLEDXPC {
    public static let defaultBundleIdentifier = "io.github.EEvan00.Glance"

    public static func serviceName(bundleIdentifier: String?) -> String {
        "\(bundleIdentifier ?? defaultBundleIdentifier).MagSafeHelper"
    }
}

@objc public protocol MagSafeLEDXPCProtocol {
    func setLEDMode(_ rawValue: UInt8, withReply reply: @escaping (Bool) -> Void)
    func renewOffLease(withReply reply: @escaping (Bool) -> Void)
}

public final class MagSafeLEDXPCService: NSObject, MagSafeLEDXPCProtocol {
    private let apply: @Sendable (MagSafeLEDCommand) -> Bool
    private let requestDidBegin: @Sendable () -> Void
    private let requestDidEnd: @Sendable () -> Void
    private let renew: @Sendable () -> Bool

    public init(
        apply: @escaping @Sendable (MagSafeLEDCommand) -> Bool,
        requestDidBegin: @escaping @Sendable () -> Void = {},
        requestDidEnd: @escaping @Sendable () -> Void = {},
        renew: @escaping @Sendable () -> Bool = { false }
    ) {
        self.apply = apply
        self.requestDidBegin = requestDidBegin
        self.requestDidEnd = requestDidEnd
        self.renew = renew
    }

    public func setLEDMode(_ rawValue: UInt8, withReply reply: @escaping (Bool) -> Void) {
        requestDidBegin()
        defer { requestDidEnd() }
        guard let command = MagSafeLEDCommand(rawValue: rawValue) else {
            reply(false)
            return
        }
        reply(apply(command))
    }

    public func renewOffLease(withReply reply: @escaping (Bool) -> Void) {
        requestDidBegin()
        defer { requestDidEnd() }
        reply(renew())
    }
}
