import Foundation
import XCTest
@testable import GlanceCore

@MainActor
final class NativeWeatherLocationTests: XCTestCase {
    func testWeatherDoesNotRequestPermissionBeforeExplicitUserActivation() async {
        let manager = WeatherLocationManagerDouble(status: .notDetermined)
        let session = NativeWeatherLocationSession(manager: manager)
        do { _ = try await session.locate(); XCTFail("Unactivated weather requested location") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationUnavailable) }
        XCTAssertEqual(manager.authorizationRequests, 0)
        XCTAssertEqual(manager.locationRequests, 0)
    }

    func testDeniedAuthorizationNeverStartsLocationUpdates() async {
        let manager = WeatherLocationManagerDouble(status: .denied)
        let request = NativeWeatherLocationRequest(manager: manager)
        do { _ = try await request.locate(); XCTFail("Denied location succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationDenied) }
        XCTAssertEqual(manager.locationRequests, 0)
    }

    func testAuthorizationGrantStartsRequestAndReturnsValidFreshCoordinate() async throws {
        let manager = WeatherLocationManagerDouble(status: .notDetermined)
        let request = NativeWeatherLocationRequest(manager: manager)
        let task = Task { try await request.locate() }
        for _ in 0..<100 where manager.authorizationRequests == 0 { await Task.yield() }
        manager.status = .authorized
        manager.onEvent?(.authorizationChanged)
        XCTAssertEqual(manager.locationRequests, 1)
        manager.onEvent?(.location(NativeWeatherLocation(latitude: -33.8, longitude: 151.2), accuracy: 20, timestamp: Date()))
        let location = try await task.value
        XCTAssertEqual(location.latitude, -33.8)
        XCTAssertTrue(manager.stopped)
    }

    func testTimeoutStopsManagerAndReportsLocationUnavailable() async {
        let manager = WeatherLocationManagerDouble(status: .authorized)
        let request = NativeWeatherLocationRequest(manager: manager, timeout: .milliseconds(1))
        do { _ = try await request.locate(); XCTFail("Missing location succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationUnavailable) }
        XCTAssertTrue(manager.stopped)
        XCTAssertNil(manager.onEvent)
    }

    func testCancellationStopsManagerWithoutPublishingAnIssue() async {
        let manager = WeatherLocationManagerDouble(status: .authorized)
        let request = NativeWeatherLocationRequest(manager: manager)
        let task = Task { try await request.locate() }
        for _ in 0..<100 where manager.locationRequests == 0 { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled location succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(manager.stopped)
        XCTAssertNil(manager.onEvent)
    }

    func testCancelledPermissionWaitDoesNotPromptAgainWhenWeatherReopens() async throws {
        let manager = WeatherLocationManagerDouble(status: .notDetermined)
        let session = NativeWeatherLocationSession(manager: manager)
        session.enableAuthorizationRequest()
        let first = Task { try await session.locate() }
        for _ in 0..<100 where manager.authorizationRequests == 0 { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled wait succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        let reopened = Task { try await session.locate() }
        for _ in 0..<100 where manager.onEvent == nil { await Task.yield() }
        XCTAssertEqual(manager.authorizationRequests, 1)
        manager.status = .authorized
        manager.onEvent?(.authorizationChanged)
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 30, longitude: 40), accuracy: 1000, timestamp: Date()))
        let location = try await reopened.value
        XCTAssertEqual(location.latitude, 30)
        XCTAssertTrue(manager.stopped)
    }

    func testImmediateReplacementWaitsForCancelledLookupCleanup() async throws {
        let manager = WeatherLocationManagerDouble(status: .authorized)
        let session = NativeWeatherLocationSession(manager: manager)
        let first = Task { try await session.locate() }
        for _ in 0..<100 where manager.locationRequests == 0 { await Task.yield() }
        first.cancel()
        // Reopen immediately, without awaiting the cancelled lookup first.
        let replacement = Task { try await session.locate() }
        for _ in 0..<1000 where manager.locationRequests < 2 { await Task.yield() }
        XCTAssertEqual(manager.locationRequests, 2)
        XCTAssertNotNil(manager.onEvent)
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 30, longitude: 40), accuracy: 1000, timestamp: Date()))
        let location = try await replacement.value
        XCTAssertEqual(location.longitude, 40)
        do { _ = try await first.value; XCTFail("Cancelled lookup succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancelledMiddleLookupCannotCancelLatestReplacement() async throws {
        let manager = WeatherLocationManagerDouble(status: .authorized)
        let session = NativeWeatherLocationSession(manager: manager)
        let first = Task { try await session.locate() }
        for _ in 0..<100 where manager.locationRequests == 0 { await Task.yield() }
        let middle = Task { try await session.locate() }
        await Task.yield()
        middle.cancel()
        first.cancel()
        let latest = Task { try await session.locate() }
        for _ in 0..<1000 where manager.locationRequests < 2 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNotNil(manager.onEvent)
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 30, longitude: 40), accuracy: 1000, timestamp: Date()))
        let location = try await latest.value
        XCTAssertEqual(location.latitude, 30)
        _ = try? await first.value
        do { _ = try await middle.value; XCTFail("Cancelled middle lookup succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStaleOrInvalidCoordinatesCannotBeUsedForWeather() async throws {
        let manager = WeatherLocationManagerDouble(status: .authorized)
        let request = NativeWeatherLocationRequest(manager: manager)
        let task = Task { try await request.locate() }
        for _ in 0..<100 where manager.locationRequests == 0 { await Task.yield() }
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 400, longitude: 0), accuracy: 20, timestamp: Date()))
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 30, longitude: 0), accuracy: -1, timestamp: Date()))
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 30, longitude: 0), accuracy: 20, timestamp: Date().addingTimeInterval(-1000)))
        manager.onEvent?(.location(NativeWeatherLocation(latitude: 40, longitude: 50), accuracy: 20, timestamp: Date()))
        let result = try await task.value
        XCTAssertEqual(result.latitude, 40)
    }
}

@MainActor
private final class WeatherLocationManagerDouble: NativeWeatherLocationManaging {
    var status: NativeWeatherAuthorization
    var servicesEnabled = true
    var onEvent: (@MainActor (NativeWeatherLocationEvent) -> Void)?
    var authorizationRequests = 0
    var locationRequests = 0
    var stopped = false
    init(status: NativeWeatherAuthorization) { self.status = status }
    func requestAuthorization() { authorizationRequests += 1 }
    func requestLocation() { locationRequests += 1 }
    func stop() { stopped = true }
}
