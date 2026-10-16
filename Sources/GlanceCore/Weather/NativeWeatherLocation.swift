import AppKit
import CoreLocation
import OSLog
import Foundation

enum NativeWeatherAuthorization: Sendable { case notDetermined, authorized, denied }

enum NativeWeatherLocationEvent: Sendable {
    case authorizationChanged
    case location(NativeWeatherLocation, accuracy: Double, timestamp: Date)
    case failed(denied: Bool)
}

@MainActor
protocol NativeWeatherLocationManaging: AnyObject {
    var status: NativeWeatherAuthorization { get }
    var servicesEnabled: Bool { get }
    var onEvent: (@MainActor (NativeWeatherLocationEvent) -> Void)? { get set }
    func requestAuthorization()
    func requestLocation()
    func stop()
}

/// Keep the permission owner alive when a system prompt dismisses the popover.
/// Cancelling a weather lookup still stops location updates, but does not destroy
/// the manager handling the user's outstanding authorization response.
@MainActor
final class NativeWeatherLocationSession: NativeWeatherLocationManaging {
    static let shared = NativeWeatherLocationSession(manager: CoreLocationWeatherManager())
    private let manager: any NativeWeatherLocationManaging
    private var requestedAuthorization = false
    private var allowsAuthorizationRequest = false
    private var activeLookup: Task<NativeWeatherLocation, Error>?
    private var activeLookupID: UUID?

    init(manager: any NativeWeatherLocationManaging) { self.manager = manager }

    func enableAuthorizationRequest() {
        allowsAuthorizationRequest = true
        // A new explicit visit/refresh may retry an unanswered system request.
        // Cancellation alone keeps the pending request, so popover dismissal
        // by the permission dialog does not issue a duplicate request.
        if status == .notDetermined { requestedAuthorization = false }
    }

    var status: NativeWeatherAuthorization { manager.status }
    var servicesEnabled: Bool { manager.servicesEnabled }
    var onEvent: (@MainActor (NativeWeatherLocationEvent) -> Void)? {
        get { manager.onEvent }
        set { manager.onEvent = newValue }
    }
    func locate() async throws -> NativeWeatherLocation {
        guard status != .notDetermined || allowsAuthorizationRequest else {
            throw NativeWeatherIssue.locationUnavailable
        }
        // Finish the previous lookup's callback cleanup before a replacement
        // installs its callback on the shared CLLocationManager.
        while let previous = activeLookup {
            try Task.checkCancellation()
            let previousID = activeLookupID
            previous.cancel()
            _ = try? await previous.value
            if activeLookupID == previousID {
                activeLookup = nil
                activeLookupID = nil
            }
        }
        try Task.checkCancellation()
        let id = UUID()
        let lookup = Task { @MainActor in
            try await NativeWeatherLocationRequest(manager: self).locate()
        }
        activeLookup = lookup
        activeLookupID = id
        defer {
            if activeLookupID == id {
                activeLookup = nil
                activeLookupID = nil
            }
        }
        return try await withTaskCancellationHandler {
            try await lookup.value
        } onCancel: {
            lookup.cancel()
        }
    }
    func requestAuthorization() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        manager.requestAuthorization()
    }
    func requestLocation() { manager.requestLocation() }
    func stop() { manager.stop() }
}

/// One bounded request includes both the permission prompt and location lookup.
/// The injected manager keeps tests away from the system permission/service APIs.
@MainActor
final class NativeWeatherLocationRequest {
    private let manager: any NativeWeatherLocationManaging
    private let timeout: Duration
    private var continuation: CheckedContinuation<NativeWeatherLocation, Error>?
    private var deadline: Task<Void, Never>?
    private var requestedLocation = false

    init(manager: any NativeWeatherLocationManaging, timeout: Duration = .seconds(15)) {
        self.manager = manager
        self.timeout = timeout
    }

    static func live() async throws -> NativeWeatherLocation {
        try await NativeWeatherLocationSession.shared.locate()
    }

    func locate() async throws -> NativeWeatherLocation {
        try Task.checkCancellation()
        guard manager.servicesEnabled else { throw NativeWeatherIssue.locationServicesDisabled }
        guard manager.status != .denied else { throw NativeWeatherIssue.locationDenied }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                // A request instance represents one location lookup at a time.
                guard self.continuation == nil else { continuation.resume(throwing: NativeWeatherIssue.locationUnavailable); return }
                self.continuation = continuation
                requestedLocation = false
                manager.onEvent = { [weak self] event in self?.receive(event) }
                deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.timedOut()
                }
                if manager.status == .notDetermined { manager.requestAuthorization() }
                else { startLocation() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func receive(_ event: NativeWeatherLocationEvent) {
        guard continuation != nil else { return }
        switch event {
        case .authorizationChanged:
            guard manager.servicesEnabled else {
                finish(.failure(NativeWeatherIssue.locationServicesDisabled))
                return
            }
            switch manager.status {
            case .denied: finish(.failure(NativeWeatherIssue.locationDenied))
            case .authorized: startLocation()
            case .notDetermined: break
            }
        case .location(let location, let accuracy, let timestamp):
            guard location.latitude.isFinite, location.longitude.isFinite,
                  (-90...90).contains(location.latitude), (-180...180).contains(location.longitude),
                  accuracy.isFinite, accuracy >= 0,
                  abs(timestamp.timeIntervalSinceNow) <= 300 else { return }
            finish(.success(location))
        case .failed(let denied):
            let issue: NativeWeatherIssue = !manager.servicesEnabled ? .locationServicesDisabled :
                (denied ? .locationDenied : .locationUnavailable)
            finish(.failure(issue))
        }
    }

    private func timedOut() {
        let issue: NativeWeatherIssue
        if !manager.servicesEnabled { issue = .locationServicesDisabled }
        else {
            switch manager.status {
            case .notDetermined: issue = .authorizationTimedOut
            case .denied: issue = .locationDenied
            case .authorized: issue = .locationUnavailable
            }
        }
        Logger(subsystem: "io.github.EEvan00.Glance", category: "WeatherLocation")
            .notice("Weather location deadline: \(String(describing: issue), privacy: .public)")
        finish(.failure(issue))
    }

    private func startLocation() {
        guard !requestedLocation else { return }
        requestedLocation = true
        manager.requestLocation()
    }

    private func finish(_ result: Result<NativeWeatherLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        manager.onEvent = nil
        manager.stop()
        continuation.resume(with: result)
    }
}

@MainActor
private final class CoreLocationWeatherManager: NSObject, NativeWeatherLocationManaging, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onEvent: (@MainActor (NativeWeatherLocationEvent) -> Void)?
    var status: NativeWeatherAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .restricted, .denied: return .denied
        @unknown default: return .denied
        }
    }
    var servicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    func requestAuthorization() {
        Logger(subsystem: "io.github.EEvan00.Glance", category: "WeatherLocation")
            .info("Requesting weather location permission; appActive=\(NSApp?.isActive ?? false)")
        manager.requestWhenInUseAuthorization()
    }
    func requestLocation() { manager.requestLocation() }
    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.onEvent?(.authorizationChanged) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let position = locations.last else { return }
        let event = NativeWeatherLocationEvent.location(
            NativeWeatherLocation(latitude: position.coordinate.latitude, longitude: position.coordinate.longitude),
            accuracy: position.horizontalAccuracy, timestamp: position.timestamp)
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let failure = error as NSError
        // Record only the system error identity, never coordinates or place names.
        Logger(subsystem: "io.github.EEvan00.Glance", category: "WeatherLocation")
            .notice("Weather location failed: \(failure.domain, privacy: .public) code=\(failure.code)")
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in self?.onEvent?(.failed(denied: denied)) }
    }
}
