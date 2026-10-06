import BatteryChargingBridge

enum BatteryChargingHold: Int, Equatable, Sendable {
    case unknown = -1
    case inactive = 0
    case paused = 1
    case resumable = 2

    static func readSystem() async -> Self {
        await Task.detached(priority: .utility) {
            Self(rawValue: Int(GlanceReadChargingHold())) ?? .unknown
        }.value
    }
}
