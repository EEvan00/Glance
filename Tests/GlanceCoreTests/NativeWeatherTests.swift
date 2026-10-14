import CoreLocation
import XCTest
@testable import GlanceCore

@MainActor
final class NativeWeatherTests: XCTestCase {
    private let result = NativeWeatherResult(
        snapshot: WeatherSnapshot(temperature: 18, code: 3, isDay: 1),
        attribution: NativeWeatherAttribution(
            combinedMarkLightURL: URL(string: "https://example.com/light.svg")!,
            combinedMarkDarkURL: URL(string: "https://example.com/dark.svg")!,
            legalPageURL: URL(string: "https://example.com/legal")!),
        updatedAt: Date(timeIntervalSince1970: 1000))

    func testCacheExpiresAtFifteenMinutesAndRefreshBypassesIt() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        var requests = 0
        let provider = NativeWeatherProvider(isAvailable: { true }, now: { now },
            location: { NativeWeatherLocation(latitude: -33, longitude: 151) },
            weather: { [result] _ in
                requests += 1
                var response = result
                response.snapshot = WeatherSnapshot(temperature: Double(requests), code: 3, isDay: 1)
                return response
            })
        let first = try await provider.fetch()
        XCTAssertEqual(first.snapshot.temperature, 1)
        now = now.addingTimeInterval(899)
        let cached = try await provider.fetch()
        XCTAssertEqual(cached.snapshot.temperature, 1)
        now = now.addingTimeInterval(1)
        let expired = try await provider.fetch()
        XCTAssertEqual(expired.snapshot.temperature, 2)
        let forced = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(forced.snapshot.temperature, 3)
    }

    func testConcurrentConsumersShareFetchAndCancelIndependently() async throws {
        let gate = WeatherTestGate()
        var requests = 0
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: -33, longitude: 151) },
            weather: { [result] _ in requests += 1; try await gate.wait(); return result })
        let current = Task { try await provider.fetch() }
        let forecast = Task { try await provider.fetch() }
        for _ in 0..<100 where requests == 0 { await Task.yield() }
        current.cancel()
        do { _ = try await current.value; XCTFail("Cancelled consumer returned weather") }
        catch { XCTAssertTrue(error is CancellationError) }
        gate.resume()
        let response = try await forecast.value
        XCTAssertEqual(response.snapshot.temperature, 18)
        XCTAssertEqual(requests, 1)
    }

    func testCancellingLastConsumerCancelsFetchAndAllowsRetry() async throws {
        var cancelled = false
        var requests = 0
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { [result] _ in
                requests += 1
                if requests == 1 {
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { cancelled = true; throw error }
                }
                return result
            })
        let request = Task { try await provider.fetch() }
        for _ in 0..<100 where requests == 0 { await Task.yield() }
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled consumer returned weather") }
        catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<100 where !cancelled { await Task.yield() }
        XCTAssertTrue(cancelled)
        let response = try await provider.fetch()
        XCTAssertEqual(response.snapshot.temperature, 18)
    }

    func testConfigurationAndErrorsAreExplicitAndFailuresAreRetryable() async throws {
        let unavailable = NativeWeatherProvider(isAvailable: { false },
            location: { XCTFail("Unconfigured provider requested location"); throw NativeWeatherIssue.locationUnavailable },
            weather: { _ in XCTFail("Unconfigured provider requested service"); throw NativeWeatherIssue.serviceUnavailable })
        do { _ = try await unavailable.fetch(); XCTFail("Unconfigured fetch succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .notConfigured) }
        var denied = true
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { if denied { throw NativeWeatherIssue.locationDenied }; return NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { [result] _ in return result })
        do { _ = try await provider.fetch(); XCTFail("Denied location succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationDenied) }
        denied = false
        let retried = try await provider.fetch()
        XCTAssertEqual(retried.snapshot.temperature, 18)
        let failed = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await failed.fetch(); XCTFail("Service failure succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .serviceUnavailable) }
    }

    func testControllerChangesSourceAndClearsNativeState() async throws {
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { [result] _ in result })
        let controller = WeatherController(nativeProvider: provider)
        XCTAssertEqual(controller.source, .shortcuts)
        controller.configure(source: .nativeWeather)
        controller.setVisible(true, shortcutName: "")
        for _ in 0..<100 where controller.isLoading { await Task.yield() }
        XCTAssertEqual(controller.snapshot?.temperature, 18)
        XCTAssertEqual(controller.attribution?.legalPageURL, result.attribution.legalPageURL)
        controller.configure(source: .shortcuts)
        XCTAssertNil(controller.snapshot)
        XCTAssertNil(controller.attribution)
        XCTAssertNil(controller.nativeIssue)
        XCTAssertFalse(controller.isLoading)
    }

    func testControllerReportsNativeFailureWithoutRunningShortcuts() async throws {
        let provider = NativeWeatherProvider(isAvailable: { false },
            location: { throw NativeWeatherIssue.locationUnavailable },
            weather: { _ in throw NativeWeatherIssue.serviceUnavailable })
        let controller = WeatherController(executable: URL(fileURLWithPath: "/no-such-shortcuts"), nativeProvider: provider)
        controller.configure(source: .nativeWeather)
        controller.setVisible(true, shortcutName: "Glance Weather")
        for _ in 0..<100 where controller.isLoading { await Task.yield() }
        XCTAssertEqual(controller.nativeIssue, .notConfigured)
        XCTAssertTrue(controller.isUnavailable)
        XCTAssertNil(controller.snapshot)
    }

    func testChangingSourceDuringFetchCannotPublishStaleNativeResult() async throws {
        let gate = WeatherTestGate()
        var started = false
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { [result] _ in started = true; try await gate.wait(); return result })
        let controller = WeatherController(nativeProvider: provider)
        controller.configure(source: .nativeWeather)
        controller.setVisible(true, shortcutName: "")
        for _ in 0..<100 where !started { await Task.yield() }
        controller.configure(source: .shortcuts)
        gate.resume()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(controller.source, .shortcuts)
        XCTAssertNil(controller.snapshot)
        XCTAssertNil(controller.attribution)
        XCTAssertNil(controller.nativeIssue)
        XCTAssertFalse(controller.isLoading)
    }

    func testChangingSourceWhileVisibleStartsNativeFetch() async throws {
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { NativeWeatherLocation(latitude: 0, longitude: 0) },
            weather: { [result] _ in result })
        let controller = WeatherController(nativeProvider: provider)
        controller.setVisible(true, shortcutName: "")
        controller.configure(source: .nativeWeather)
        for _ in 0..<100 where controller.isLoading { await Task.yield() }
        XCTAssertEqual(controller.snapshot?.temperature, 18)
        XCTAssertFalse(controller.isUnavailable)
    }

    func testUnknownLocationFailureIsNotReportedAsAServiceFailure() async {
        let provider = NativeWeatherProvider(isAvailable: { true },
            location: { throw URLError(.timedOut) },
            weather: { _ in XCTFail("Missing location requested weather"); throw NativeWeatherIssue.serviceUnavailable })
        do { _ = try await provider.fetch(); XCTFail("Missing location succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationUnavailable) }
    }

}

@MainActor
private final class WeatherTestGate {
    var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}
