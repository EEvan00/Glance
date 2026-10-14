import CoreLocation
import Foundation

/// Deliberately carries only city/region fields; street names and addresses are
/// neither copied out of CLPlacemark nor retained in the weather cache.
struct NativeWeatherPlace: Sendable {
    let locality: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?

    var displayName: String? {
        for value in [locality, subAdministrativeArea, administrativeArea] {
            guard let value else { continue }
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            return name
        }
        return nil
    }
}

@MainActor
protocol NativeWeatherGeocoding: AnyObject {
    func reverseGeocode(_ location: NativeWeatherLocation, preferredLocale: Locale,
                        completion: @escaping @Sendable (NativeWeatherPlace?) -> Void)
    func cancel()
}

/// Place lookup is optional weather enrichment. Timeouts, errors and cancellation
/// yield no name, preserving the weather result and existing location fallback.
@MainActor
final class NativeWeatherPlaceNameRequest {
    private let manager: any NativeWeatherGeocoding
    private let locale: Locale
    private let timeout: Duration
    private var continuation: CheckedContinuation<String?, Never>?
    private var requestID: UUID?
    private var deadline: Task<Void, Never>?

    init(manager: any NativeWeatherGeocoding, locale: Locale = .current,
         timeout: Duration = .seconds(4)) {
        self.manager = manager
        self.locale = locale
        self.timeout = timeout
    }

    static func live(for location: NativeWeatherLocation) async -> String? {
        await NativeWeatherPlaceNameRequest(manager: CoreLocationWeatherGeocoder()).name(for: location)
    }

    func name(for location: NativeWeatherLocation) async -> String? {
        guard !Task.isCancelled, location.latitude.isFinite, location.longitude.isFinite,
              (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else { return nil }
        let id = UUID()
        let name: String? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, self.continuation == nil else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                requestID = id
                deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(nil, requestID: id, cancelGeocoder: true)
                }
                let rounded = NativeWeatherLocation(latitude: (location.latitude * 100).rounded() / 100,
                                                    longitude: (location.longitude * 100).rounded() / 100)
                manager.reverseGeocode(rounded, preferredLocale: locale) { [weak self] place in
                    Task { @MainActor [weak self] in self?.finish(place?.displayName, requestID: id) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, requestID: id, cancelGeocoder: true) }
        }
        return Task.isCancelled ? nil : name
    }

    private func finish(_ name: String?, requestID id: UUID, cancelGeocoder: Bool = false) {
        guard requestID == id, let continuation else { return }
        self.continuation = nil
        requestID = nil
        deadline?.cancel()
        deadline = nil
        if cancelGeocoder { manager.cancel() }
        continuation.resume(returning: name)
    }
}

@MainActor
private final class CoreLocationWeatherGeocoder: NativeWeatherGeocoding {
    private let geocoder = CLGeocoder()

    func reverseGeocode(_ location: NativeWeatherLocation, preferredLocale: Locale,
                        completion: @escaping @Sendable (NativeWeatherPlace?) -> Void) {
        let coordinate = CLLocation(latitude: location.latitude, longitude: location.longitude)
        geocoder.reverseGeocodeLocation(coordinate, preferredLocale: preferredLocale) { placemarks, error in
            guard error == nil, let place = placemarks?.first else { completion(nil); return }
            completion(NativeWeatherPlace(locality: place.locality,
                                          subAdministrativeArea: place.subAdministrativeArea,
                                          administrativeArea: place.administrativeArea))
        }
    }

    func cancel() { geocoder.cancelGeocode() }
}
