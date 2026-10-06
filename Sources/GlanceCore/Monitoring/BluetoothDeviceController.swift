import AppKit
@preconcurrency import CoreBluetooth
import Foundation
import IOBluetooth

enum BluetoothWorkerResult: Sendable {
    case success([BluetoothDevice])
    case poweredOff
    case unavailable
    case failed
}

protocol BluetoothPairedDeviceReading: AnyObject {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void)
    func invalidateMetadata()
}

extension BluetoothPairedDeviceReading {
    func invalidateMetadata() {}
}

@MainActor
protocol BluetoothStateMonitoring: AnyObject {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)? { get set }
    func start()
    func stop()
}


/// Reads only the operating system paired-device database. It deliberately
/// does not perform a Bluetooth inquiry, so nearby BLE advertisements never
/// appear as paired devices.
final class IOBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    private let queue = DispatchQueue(label: "Glance.IOBluetoothPairedDeviceWorker")
    // Accessed only on queue. At most one system report per minute while the
    // popup is active; reconnecting a device invalidates the cached snapshot.
    private var metadata: [String: BluetoothDeviceMetadata] = [:]
    private var metadataReadAt: Date?
    private var metadataConnectedIDs: Set<String> = []

    func invalidateMetadata() {
        queue.async { self.metadataReadAt = nil }
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        queue.async {
            guard let controller = IOBluetoothHostController.default() else {
                completion(.unavailable)
                return
            }
            // IOBluetoothHostController reports the HCI adapter state. The
            // previous inverted comparison reported powered off when it was on.
            guard controller.powerState == kBluetoothHCIPowerStateON else {
                completion(.poweredOff)
                return
            }
            // A nil result is not documented as an empty paired list, so it is
            // surfaced as a read failure rather than silently showing no devices.
            guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
                completion(.failed)
                return
            }

            let connectedIDs = Set(pairedDevices.filter { $0.isConnected() }.compactMap(\.addressString))
            if self.metadataReadAt == nil || Date().timeIntervalSince(self.metadataReadAt!) >= 60 || connectedIDs != self.metadataConnectedIDs {
                self.metadata = SystemProfilerBluetoothMetadata.read()
                self.metadataReadAt = Date()
                self.metadataConnectedIDs = connectedIDs
            }
            let devices = pairedDevices.compactMap { device -> BluetoothDevice? in
                guard let identifier = device.addressString, !identifier.isEmpty else { return nil }
                let details = self.metadata[BluetoothDeviceMetadata.addressKey(identifier)]
                let name = details?.name ?? device.nameOrAddress ?? identifier
                let item = BluetoothDevice(
                    id: identifier,
                    name: name,
                    kind: self.kind(for: Int(device.deviceClassMajor)),
                    isConnected: device.isConnected(),
                    metadata: details
                )
                return BluetoothDevicePresentation.isVisibleAccessory(item) ? item : nil
            }
            completion(.success(devices))
        }
    }

    private func kind(for majorClass: Int) -> BluetoothDeviceKind {
        // Bluetooth Class-of-Device major values are defined by the Bluetooth
        // specification. Unknown values remain generic rather than guessed.
        switch majorClass {
        case 0x01: .computer
        case 0x02: .phone
        case 0x04: .audio
        case 0x05: .peripheral
        default: .unknown
        }
    }
}

/// CoreBluetooth supplies the app authorization and the asynchronous adapter
/// lifecycle. IOBluetooth is intentionally not treated as an authorization
/// authority; it is used only for the paired-device database above.
@MainActor
final class CoreBluetoothStateMonitor: NSObject, @preconcurrency CBCentralManagerDelegate, BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private var centralManager: CBCentralManager?

    func start() {
        guard centralManager == nil else {
            publishState()
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        publishState()
    }

    func stop() {
        centralManager?.delegate = nil
        centralManager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState()
    }

    private func publishState() {
        onStateChange?(authorizationStatus(), managerState())
    }

    private func authorizationStatus() -> BluetoothAuthorizationStatus {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private func managerState() -> BluetoothManagerState {
        switch centralManager?.state ?? .unknown {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}

@MainActor
final class BluetoothDeviceController: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var availability: BluetoothAvailability = .idle
    @Published private(set) var connectionDeviceID: String?
    @Published private(set) var connectionFailedDeviceID: String?

    private let volumeRestorer: BluetoothVolumeRestorer
    private let connections: any BluetoothConnectionManaging

    private let worker: any BluetoothPairedDeviceReading
    private let stateMonitor: any BluetoothStateMonitoring
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var isActive = false
    private var requestGate = AsyncRequestGate()
    private var periodicRefreshTask: Task<Void, Never>?
    private var connectionRefreshTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var applicationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(
        worker: any BluetoothPairedDeviceReading = IOBluetoothPairedDeviceWorker(),
        connections: any BluetoothConnectionManaging = IOBluetoothConnectionManager(),
        volumeRestorer: BluetoothVolumeRestorer = BluetoothVolumeRestorer(),
        stateMonitor: any BluetoothStateMonitoring = CoreBluetoothStateMonitor(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.worker = worker
        self.connections = connections
        self.volumeRestorer = volumeRestorer
        self.stateMonitor = stateMonitor
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        stateMonitor.onStateChange = { [weak self] authorization, managerState in
            self?.receiveSystemState(authorization: authorization, managerState: managerState)
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
        connectionRefreshTask?.cancel()
    }


    var connectedDevices: [BluetoothDevice] {
        BluetoothDevicePresentation.grouped(devices).connected
    }

    /// Summary reads must not trigger the first Bluetooth permission prompt.
    func activateIfAuthorized() {
        guard CBManager.authorization == .allowedAlways else { return }
        activate()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        registerSystemObservers()
        stateMonitor.start()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        connectionGeneration += 1
        connectionRefreshTask?.cancel()
        connectionRefreshTask = nil
        connectionDeviceID = nil
        _ = requestGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        removeSystemObservers()
        stateMonitor.stop()
        // Closing the detail view does not invalidate the last known state.
    }

    func refresh(forceMetadata: Bool = false) {
        guard isActive, availability == .available, connectionDeviceID == nil else { return }
        if forceMetadata { worker.invalidateMetadata() }
        let request = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.requestGate.accepts(request) else { return }
                switch result {
                case let .success(devices):
                    self.devices = devices
                    self.availability = .available
                case .poweredOff:
                    self.availability = .poweredOff
                    self.stopPeriodicRefresh()
                case .unavailable:
                    self.availability = .unavailable
                    self.stopPeriodicRefresh()
                case .failed:
                    self.availability = .failed
                }
            }
        }
    }

    func toggleConnection(to device: BluetoothDevice) {
        guard isActive, availability == .available, connectionDeviceID == nil,
              let current = devices.first(where: { $0.id == device.id }) else { return }
        connectionDeviceID = current.id
        connectionFailedDeviceID = nil
        connectionGeneration += 1
        let generation = connectionGeneration
        let desired = !current.isConnected
        if !desired { volumeRestorer.capture(current) }
        _ = requestGate.advance()
        connections.setConnected(desired, deviceID: current.id) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.connectionGeneration == generation else { return }
                guard success else {
                    self.connectionDeviceID = nil
                    self.connectionFailedDeviceID = current.id
                    self.refresh()
                    return
                }
                self.connectionRefreshTask = Task { @MainActor [weak self] in
                    await self?.confirmConnection(deviceID: current.id, desired: desired, generation: generation)
                }
            }
        }
    }

    private func confirmConnection(deviceID: String, desired: Bool, generation: Int) async {
        var confirmed = false
        // A successful API return is not proof that the paired-device snapshot
        // has changed yet. Publish each fresh snapshot until it confirms the
        // requested state, and keep the action busy in the meantime.
        for attempt in 0..<16 {
            guard !Task.isCancelled, isActive, connectionGeneration == generation else { return }
            let result: BluetoothWorkerResult = await withCheckedContinuation { continuation in
                worker.read { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled, isActive, connectionGeneration == generation else { return }
            guard case let .success(updated) = result else { break }
            devices = updated
            if updated.first(where: { $0.id == deviceID })?.isConnected == desired {
                if desired, volumeRestorer.restore(deviceID) == nil {
                    // Bluetooth can connect before CoreAudio publishes the
                    // endpoint. Wait for its persistent UID before restoring.
                } else {
                    confirmed = true
                    break
                }
            }
            if attempt < 15 {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
        connectionDeviceID = nil
        connectionFailedDeviceID = confirmed ? nil : deviceID
        connectionRefreshTask = nil
    }

    private func receiveSystemState(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) {
        guard isActive else { return }
        let mappedAvailability = BluetoothAvailabilityMapper.preliminary(
            authorization: authorization,
            managerState: managerState
        )
        availability = mappedAvailability

        if mappedAvailability == .available {
            schedulePeriodicRefresh()
            refresh()
        } else {
            _ = requestGate.advance()
            stopPeriodicRefresh()
        }
    }

    private func registerSystemObservers() {
        guard applicationObserver == nil, wakeObserver == nil else { return }
        applicationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
        wakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
    }

    private func removeSystemObservers() {
        if let applicationObserver {
            notificationCenter.removeObserver(applicationObserver)
        }
        if let wakeObserver {
            workspaceNotificationCenter.removeObserver(wakeObserver)
        }
        applicationObserver = nil
        wakeObserver = nil
    }

    private func refreshAfterSystemEvent() {
        guard isActive else { return }
        stateMonitor.start()
    }

    private func schedulePeriodicRefresh() {
        guard periodicRefreshTask == nil else { return }
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.isActive, self.availability == .available else { return }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }
}
