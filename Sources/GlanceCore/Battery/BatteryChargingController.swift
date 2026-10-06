import BatteryChargingBridge
import Combine

@MainActor
final class BatteryChargingController: ObservableObject {
    enum Result: Equatable {
        case accepted
        case failed
    }

    @Published private(set) var isRequesting = false
    @Published private(set) var result: Result?
    private let request: @Sendable () async -> Bool

    init(request: @escaping @Sendable () async -> Bool = {
        await Task.detached(priority: .userInitiated) { GlanceChargeToFullNow() }.value
    }) {
        self.request = request
    }

    func clearResult() {
        guard !isRequesting else { return }
        result = nil
    }

    func reportResumeTimeout() {
        guard result == .accepted else { return }
        result = .failed
    }

    func chargeToFull(battery: BatteryStatus) async {
        guard battery.canChargeToFull, !isRequesting, result != .accepted else { return }
        isRequesting = true
        result = nil
        let accepted = await request()
        result = accepted ? .accepted : .failed
        isRequesting = false
        // Acceptance is not a charging reading. IOPS remains the source of truth.
    }
}
