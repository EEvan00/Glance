// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import Foundation
import IOKit.ps
import OSLog

private let batteryMonitorLogger = Logger(
    subsystem: "io.github.EEvan00.Glance",
    category: "battery"
)

struct BatteryReading: Equatable {
    var currentCapacity: Int
    var maxCapacity: Int
    var isCharging: Bool
    var isCharged: Bool = false
    var timeToFullChargeMinutes: Int? = nil
    var isConnectedToPower: Bool
    var isPresent: Bool
}

protocol BatteryReadingProviding: AnyObject {
    func read() -> BatteryReading?
}

typealias IOPSNotificationCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias IOPSRunLoopSourceFactory = (
    UnsafeMutableRawPointer?,
    IOPSNotificationCallback
) -> CFRunLoopSource?

private final class BatteryCallbackContext: @unchecked Sendable {
    weak var monitor: BatteryMonitor?

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
    }
}

final class IOPSBatteryReader: BatteryReadingProviding {
    func read() -> BatteryReading? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let reading = Self.parse(description)
            else { continue }

            return reading
        }

        return nil
    }

    static func parse(_ description: [String: Any]) -> BatteryReading? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
            return nil
        }
        guard
            let current = integerValue(description[kIOPSCurrentCapacityKey]),
            let maximum = integerValue(description[kIOPSMaxCapacityKey])
        else { return nil }

        let rawTimeToFullCharge = integerValue(description[kIOPSTimeToFullChargeKey])
        let timeToFullCharge = rawTimeToFullCharge.flatMap { $0 > 0 ? $0 : nil }

        return BatteryReading(
            currentCapacity: current,
            maxCapacity: maximum,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            timeToFullChargeMinutes: timeToFullCharge,
            isConnectedToPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            isPresent: description[kIOPSIsPresentKey] as? Bool ?? true
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

@MainActor
final class BatteryMonitor: BatteryMonitoring {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    private let reader: any BatteryReadingProviding
    private let lowPowerModeProvider: () -> Bool
    private let iopsRunLoopSourceFactory: IOPSRunLoopSourceFactory
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
    nonisolated(unsafe) private var callbackContext: Unmanaged<BatteryCallbackContext>?
    private var lifecycle = Lifecycle.idle
    private let chargingHoldProvider: @Sendable () async -> BatteryChargingHold
    private var holdTask: Task<Void, Never>?
    private var cachedHold: BatteryChargingHold = .unknown
    private var refreshRevision = 0
    private var latestStatus: BatteryStatus?

    init(
        reader: any BatteryReadingProviding = IOPSBatteryReader(),
        chargingHoldProvider: @escaping @Sendable () async -> BatteryChargingHold = {
            await BatteryChargingHold.readSystem()
        },
        lowPowerModeProvider: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        iopsRunLoopSourceFactory: @escaping IOPSRunLoopSourceFactory = { context, callback in
            IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        }
    ) {
        self.reader = reader
        self.chargingHoldProvider = chargingHoldProvider
        self.lowPowerModeProvider = lowPowerModeProvider
        self.iopsRunLoopSourceFactory = iopsRunLoopSourceFactory
        (updates, continuation) = MonitorStream.make(of: BatteryStatus.self)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        if let callbackContext {
            callbackContext.release()
        }
        continuation.finish()
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        installNotifications()
        refresh()
    }

    func recover() {
        guard lifecycle == .running else { return }

        teardownNotifications()
        installNotifications()
    }

    private func installNotifications() {

        let context = Unmanaged.passRetained(BatteryCallbackContext(monitor: self))
        callbackContext = context

        let callback: IOPSNotificationCallback = { contextPointer in
            guard let contextPointer else { return }
            let callbackContext = Unmanaged<BatteryCallbackContext>
                .fromOpaque(contextPointer)
                .takeUnretainedValue()
            guard let monitor = callbackContext.monitor else { return }
            Task { @MainActor in
                monitor.refresh()
            }
        }

        if let source = iopsRunLoopSourceFactory(context.toOpaque(), callback) {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            batteryMonitorLogger.error(
                "IOPS notification source unavailable; fallback refresh remains active"
            )
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        holdTask?.cancel()
        holdTask = nil
        teardownNotifications()
        continuation.finish()
    }

    func refresh() {
        guard lifecycle != .stopped else { return }

        let reading = reader.read()
        var status: BatteryStatus

        if let reading, reading.isPresent {
            let percentage = reading.maxCapacity > 0
                ? Int((Double(reading.currentCapacity) / Double(reading.maxCapacity) * 100).rounded())
                : reading.currentCapacity
            status = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: reading.isCharging,
                isCharged: reading.isCharged,
                timeToFullChargeMinutes: reading.isCharging
                    ? reading.timeToFullChargeMinutes
                    : nil,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: reading.isConnectedToPower
            )
        } else {
            status = BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isCharged: false,
                timeToFullChargeMinutes: nil,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: false
            )
        }

        if !status.canHaveChargingHold { cachedHold = .unknown }
        status.chargingHold = cachedHold
        if latestStatus != status { refreshRevision += 1 }
        latestStatus = status
        continuation.yield(status)
        refreshChargingHold(for: status)
    }

    private func refreshChargingHold(for status: BatteryStatus) {
        guard status.canHaveChargingHold, holdTask == nil else { return }
        let revision = refreshRevision
        let provider = chargingHoldProvider
        holdTask = Task { @MainActor [weak self] in
            let hold = await provider()
            guard !Task.isCancelled, let self, self.lifecycle != .stopped else { return }
            self.holdTask = nil
            guard var current = self.latestStatus, current.canHaveChargingHold else { return }
            guard self.refreshRevision == revision else {
                self.refreshChargingHold(for: current)
                return
            }
            self.cachedHold = hold
            current.chargingHold = hold
            self.latestStatus = current
            self.continuation.yield(current)
        }
    }

    private func teardownNotifications() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        if let callbackContext {
            callbackContext.release()
            self.callbackContext = nil
        }
    }
}
