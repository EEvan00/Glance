import Foundation

enum WeatherSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case nativeWeather, shortcuts
    var id: String { rawValue }
}

enum NativeWeatherConfiguration {
    static var serviceURL: URL? { serviceURL(from: Bundle.main.object(forInfoDictionaryKey: "GlanceWeatherServiceURL") as? String) }
    static var isAvailable: Bool { serviceURL != nil }

    static func serviceURL(from raw: String?) -> URL? {
        guard let raw, !raw.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443, parts.path == "/v1/weather",
              host.contains("."), ![".local", ".localhost", ".internal", ".test", ".invalid"].contains(where: { host.hasSuffix($0) }),
              let url = parts.url else { return nil }
        return url
    }
}

enum NativeWeatherIssue: Error, Equatable, Sendable {
    case notConfigured, locationDenied, locationUnavailable, serviceUnavailable
}

struct NativeWeatherAttribution: Codable, Equatable, Sendable {
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
    let legalPageURL: URL
}

struct NativeWeatherLocation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct NativeWeatherResult: Equatable, Sendable {
    var snapshot: WeatherSnapshot
    let attribution: NativeWeatherAttribution
    let updatedAt: Date
}

/// Shared current/forecast cache. Each consumer owns a waiter; only cancelling the
/// last waiter cancels the location/service request used by both views.
@MainActor
final class NativeWeatherProvider {
    static let shared = NativeWeatherProvider(isAvailable: { NativeWeatherConfiguration.isAvailable },
        location: { try await NativeWeatherLocationRequest.live() },
        weather: { location in
            guard let endpoint = NativeWeatherConfiguration.serviceURL else { throw NativeWeatherIssue.notConfigured }
            return try await NativeWeatherRESTClient(endpoint: endpoint).fetch(location)
        }, placeName: { location in await NativeWeatherPlaceNameRequest.live(for: location) })
    private let isAvailable: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let location: @MainActor () async throws -> NativeWeatherLocation
    private let weather: @MainActor (NativeWeatherLocation) async throws -> NativeWeatherResult
    private let placeName: @MainActor (NativeWeatherLocation) async -> String?
    private var cached: NativeWeatherResult?
    private var cachedAt: Date?
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    private var waiters: [UUID: CheckedContinuation<NativeWeatherResult, Error>] = [:]

    init(isAvailable: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() },
         location: @escaping @MainActor () async throws -> NativeWeatherLocation,
         weather: @escaping @MainActor (NativeWeatherLocation) async throws -> NativeWeatherResult,
         placeName: @escaping @MainActor (NativeWeatherLocation) async -> String? = { _ in nil }) {
        self.isAvailable = isAvailable
        self.now = now
        self.location = location
        self.weather = weather
        self.placeName = placeName
    }

    func fetch(forceRefresh: Bool = false) async throws -> NativeWeatherResult {
        try Task.checkCancellation()
        guard isAvailable() else { throw NativeWeatherIssue.notConfigured }
        if !forceRefresh, let cached, let cachedAt,
           (0..<900).contains(now().timeIntervalSince(cachedAt)) { return cached }
        let waiterID = UUID()
        let response: NativeWeatherResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NativeWeatherResult, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters[waiterID] = continuation
                guard request == nil else { return }
                let id = UUID()
                requestID = id
                request = Task { [weak self, location, weather, placeName] in
                    let result: Result<NativeWeatherResult, Error>
                    do {
                        let position: NativeWeatherLocation
                        do { position = try await location() }
                        catch is CancellationError { throw CancellationError() }
                        catch let issue as NativeWeatherIssue { throw issue }
                        catch { throw NativeWeatherIssue.locationUnavailable }
                        try Task.checkCancellation()
                        let nameLookup = Task { @MainActor in await placeName(position) }
                        defer { nameLookup.cancel() }
                        let response: NativeWeatherResult = try await withTaskCancellationHandler {
                            var response = try await weather(position)
                            if let name = await nameLookup.value { response.snapshot.location = name }
                            return response
                        } onCancel: {
                            nameLookup.cancel()
                        }
                        try Task.checkCancellation()
                        result = .success(response)
                    } catch is CancellationError {
                        result = .failure(CancellationError())
                    } catch let issue as NativeWeatherIssue {
                        result = .failure(issue)
                    } catch {
                        result = .failure(NativeWeatherIssue.serviceUnavailable)
                    }
                    self?.complete(result, requestID: id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(waiterID) }
        }
        try Task.checkCancellation()
        return response
    }

    private func complete(_ result: Result<NativeWeatherResult, Error>, requestID id: UUID) {
        // A cancelled request may finish after a replacement request has started.
        guard requestID == id else { return }
        if case .success(let response) = result { cached = response; cachedAt = now() }
        let completed = waiters.values
        waiters = [:]
        request = nil
        requestID = nil
        for continuation in completed { continuation.resume(with: result) }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        if waiters.isEmpty {
            request?.cancel()
            request = nil
            requestID = nil
        }
    }
}
