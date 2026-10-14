import Foundation
import XCTest
@testable import GlanceCore

@MainActor
final class NativeWeatherPlaceNameTests: XCTestCase {
    func testUsesCityLevelNamesWithRegionalFallbacksAndSanitizesInvalidNames() {
        XCTAssertEqual(NativeWeatherPlace(locality: " Sydney ", subAdministrativeArea: "Greater Sydney", administrativeArea: "NSW").displayName, "Sydney")
        XCTAssertEqual(NativeWeatherPlace(locality: "", subAdministrativeArea: "Greater Sydney", administrativeArea: "NSW").displayName, "Greater Sydney")
        XCTAssertEqual(NativeWeatherPlace(locality: nil, subAdministrativeArea: nil, administrativeArea: "東京都").displayName, "東京都")
        XCTAssertEqual(NativeWeatherPlace(locality: "Bad\nAddress", subAdministrativeArea: nil, administrativeArea: "NSW").displayName, "NSW")
        XCTAssertNil(NativeWeatherPlace(locality: nil, subAdministrativeArea: nil, administrativeArea: nil).displayName)
    }

    func testRoundsCoordinatesBeforeGeocoderAndUsesPreferredLocale() async {
        let manager = WeatherGeocoderDouble()
        let lookup = NativeWeatherPlaceNameRequest(manager: manager, locale: Locale(identifier: "zh_Hans"))
        let task = Task { await lookup.name(for: NativeWeatherLocation(latitude: -33.8688, longitude: 151.2093)) }
        for _ in 0..<100 where manager.completion == nil { await Task.yield() }
        XCTAssertEqual(manager.location, NativeWeatherLocation(latitude: -33.87, longitude: 151.21))
        XCTAssertEqual(manager.locale?.identifier, "zh-Hans")
        manager.completion?(NativeWeatherPlace(locality: "悉尼", subAdministrativeArea: nil, administrativeArea: "新南威尔士州"))
        let name = await task.value
        XCTAssertEqual(name, "悉尼")
    }

    func testGeocoderFailureReturnsNoName() async {
        let manager = WeatherGeocoderDouble()
        let lookup = NativeWeatherPlaceNameRequest(manager: manager)
        let task = Task { await lookup.name(for: NativeWeatherLocation(latitude: 40, longitude: 50)) }
        for _ in 0..<100 where manager.completion == nil { await Task.yield() }
        manager.completion?(nil)
        let name = await task.value
        XCTAssertNil(name)
    }

    func testTimeoutCancelsGeocoderAndIgnoresItsLateCallback() async {
        let manager = WeatherGeocoderDouble()
        let lookup = NativeWeatherPlaceNameRequest(manager: manager, timeout: .milliseconds(1))
        let name = await lookup.name(for: NativeWeatherLocation(latitude: 40, longitude: 50))
        XCTAssertNil(name)
        XCTAssertTrue(manager.cancelled)
        manager.completion?(NativeWeatherPlace(locality: "Late city", subAdministrativeArea: nil, administrativeArea: nil))
        for _ in 0..<10 { await Task.yield() }
    }

    func testCancellationCancelsGeocoderAndDoesNotReturnAPlace() async {
        let manager = WeatherGeocoderDouble()
        let lookup = NativeWeatherPlaceNameRequest(manager: manager)
        let task = Task { await lookup.name(for: NativeWeatherLocation(latitude: 40, longitude: 50)) }
        for _ in 0..<100 where manager.completion == nil { await Task.yield() }
        task.cancel()
        let name = await task.value
        XCTAssertNil(name)
        XCTAssertTrue(manager.cancelled)
    }

    func testWeatherAndPlaceLookupRunInParallelAndShareTheCache() async throws {
        let weatherGate = PlaceNameTestGate()
        let nameGate = PlaceNameTestGate()
        var weatherStarted = false
        var placeStarted = false
        var nameRequests = 0
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: -33.8, longitude: 151.2) },
            weather: { _ in weatherStarted = true; try await weatherGate.wait(); return Self.weatherResult },
            placeName: { _ in placeStarted = true; nameRequests += 1; try? await nameGate.wait(); return "Sydney" })
        let summary = Task { try await provider.fetch() }
        let details = Task { try await provider.fetch() }
        for _ in 0..<100 where !weatherStarted || !placeStarted { await Task.yield() }
        XCTAssertTrue(weatherStarted)
        XCTAssertTrue(placeStarted)
        weatherGate.resume()
        nameGate.resume()
        let summaryResult = try await summary.value
        let detailsResult = try await details.value
        XCTAssertEqual(summaryResult.snapshot.location, "Sydney")
        XCTAssertEqual(detailsResult.snapshot.location, "Sydney")
        let cached = try await provider.fetch()
        XCTAssertEqual(cached.snapshot.location, "Sydney")
        XCTAssertEqual(nameRequests, 1)
    }

    func testUnavailablePlaceDoesNotFailWeather() async throws {
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { _ in Self.weatherResult }, placeName: { _ in nil })
        let response = try await provider.fetch()
        XCTAssertEqual(response.snapshot.temperature, 18)
        XCTAssertNil(response.snapshot.location)
    }

    func testCancellingWeatherConsumerCancelsParallelGeocoding() async {
        let manager = WeatherGeocoderDouble()
        let lookup = NativeWeatherPlaceNameRequest(manager: manager)
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { _ in Self.weatherResult }, placeName: { location in await lookup.name(for: location) })
        let task = Task { try await provider.fetch() }
        for _ in 0..<100 where manager.completion == nil { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled weather returned a result") }
        catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<100 where !manager.cancelled { await Task.yield() }
        XCTAssertTrue(manager.cancelled)
    }

    private static var weatherResult: NativeWeatherResult {
        NativeWeatherResult(snapshot: WeatherSnapshot(temperature: 18, code: 3, isDay: 1),
            attribution: NativeWeatherAttribution(combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/light.svg")!,
                combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/dark.svg")!, legalPageURL: URL(string: "https://weatherkit.apple.com/legal")!),
            updatedAt: Date())
    }
}

@MainActor
private final class WeatherGeocoderDouble: NativeWeatherGeocoding {
    var location: NativeWeatherLocation?
    var locale: Locale?
    var completion: (@Sendable (NativeWeatherPlace?) -> Void)?
    var cancelled = false
    func reverseGeocode(_ location: NativeWeatherLocation, preferredLocale: Locale,
                        completion: @escaping @Sendable (NativeWeatherPlace?) -> Void) {
        self.location = location
        locale = preferredLocale
        self.completion = completion
    }
    func cancel() { cancelled = true }
}

@MainActor
private final class PlaceNameTestGate {
    private var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}
