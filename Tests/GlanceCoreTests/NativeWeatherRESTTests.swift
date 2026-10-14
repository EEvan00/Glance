import Foundation
import XCTest
@testable import GlanceCore

@MainActor
final class NativeWeatherRESTTests: XCTestCase {
    private let endpoint = URL(string: "https://weather.example.com/v1/weather")!
    private let fixture = Data(#"""
    {
      "weather": {
        "currentWeather": {"asOf":"2026-10-13T04:00:00.123Z","temperature":18,"conditionCode":"MostlyCloudy","daylight":true,"uvIndex":3},
        "forecastHourly": {"hours":[
          {"forecastStart":"2026-10-13T04:00:00Z","temperature":18,"conditionCode":"Rain","daylight":true,"precipitationChance":0.25},
          {"forecastStart":"2026-10-13T05:00:00Z","temperature":17,"conditionCode":"FutureCode","daylight":false,"precipitationChance":0.5}
        ]},
        "forecastDaily": {"days":[
          {"forecastStart":"2026-10-12T13:00:00Z","temperatureMin":12,"temperatureMax":23,"sunrise":"2026-10-12T19:00:00Z","sunset":"2026-10-13T08:00:00Z"},
          {"forecastStart":"2026-10-13T13:00:00Z","temperatureMin":11,"temperatureMax":22,"sunrise":"2026-10-13T19:00:00Z","sunset":"2026-10-14T08:00:00Z"}
        ]}
      },
      "attribution": {"combinedMarkLightURL":"https://weatherkit.apple.com/light.svg","combinedMarkDarkURL":"https://weatherkit.apple.com/dark.svg","legalPageURL":"https://weatherkit.apple.com/legal"}
    }
    """#.utf8)

    func testMapsAppleRESTUnitsConditionsSolarEventsAndFractionalDates() throws {
        let result = try NativeWeatherRESTClient.decode(fixture)
        XCTAssertEqual(result.snapshot.temperature, 18)
        XCTAssertEqual(result.snapshot.code, 3)
        XCTAssertEqual(result.snapshot.isDay, 1)
        XCTAssertEqual(result.snapshot.low, 12)
        XCTAssertEqual(result.snapshot.high, 23)
        XCTAssertEqual(result.snapshot.uvIndex, 3)
        XCTAssertEqual(result.snapshot.precipitationChance, 25)
        XCTAssertEqual(result.snapshot.hourly?.first?.code, 61)
        XCTAssertEqual(result.snapshot.hourly?.last?.code, 999)
        XCTAssertEqual(result.snapshot.hourly?.last?.isDay, 0)
        XCTAssertEqual(result.snapshot.hourly?.last?.precipitationChance, 50)
        XCTAssertEqual(result.snapshot.sunrises?.count, 2)
        XCTAssertEqual(result.updatedAt.timeIntervalSince1970, 1791864000.123, accuracy: 0.001)
        XCTAssertEqual(result.attribution.legalPageURL.host, "weatherkit.apple.com")
    }

    func testRequestRoundsCoordinatesAndSendsNoCredentials() throws {
        let client = NativeWeatherRESTClient(endpoint: endpoint, timeZone: { "Australia/Sydney" })
        let request = try client.request(for: NativeWeatherLocation(latitude: -33.8688, longitude: 151.2093))
        let items = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "latitude" }?.value, "-33.87")
        XCTAssertEqual(items.first { $0.name == "longitude" }?.value, "151.21")
        XCTAssertEqual(items.first { $0.name == "language" }?.value, "en")
        XCTAssertEqual(items.first { $0.name == "timezone" }?.value, "Australia/Sydney")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertLessThanOrEqual(request.timeoutInterval, 30)
    }

    func testInvalidConfigurationAndCoordinatesCannotReachTransport() async throws {
        for raw in ["http://weather.example.com/v1/weather", "https://user:secret@weather.example.com/v1/weather", "https://weather.example.com/v1/weather?key=secret", "https://weather.example.com/v1/weather#part", "invalid"] {
            XCTAssertNil(NativeWeatherConfiguration.serviceURL(from: raw), raw)
        }
        XCTAssertNotNil(NativeWeatherConfiguration.serviceURL(from: endpoint.absoluteString))
        let client = NativeWeatherRESTClient(endpoint: endpoint, load: { _ in
            XCTFail("Invalid coordinate reached transport"); throw URLError(.badURL)
        })
        do { _ = try await client.fetch(NativeWeatherLocation(latitude: .nan, longitude: 0)); XCTFail("Invalid coordinate succeeded") }
        catch { XCTAssertEqual(error as? NativeWeatherIssue, .locationUnavailable) }
    }

    func testMalformedDataInvalidAttributionAndOversizedResponsesFailExplicitly() throws {
        for text in [String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "https://weatherkit.apple.com", with: "https://apple.com.evil.test"),
                     String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "https://weatherkit.apple.com", with: "http://weatherkit.apple.com"),
                     String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "\"temperature\":18", with: "\"temperature\":1000"), "{}"] {
            XCTAssertThrowsError(try NativeWeatherRESTClient.decode(Data(text.utf8)))
        }
        XCTAssertThrowsError(try NativeWeatherRESTClient.decode(Data(repeating: 32, count: 1_048_577)))
    }

    func testHTTPFailureAndRedirectedResponsesAreRejected() async {
        for (url, status) in [(endpoint, 503), (URL(string: "https://other.example.com/v1/weather")!, 200), (URL(string: "http://weather.example.com/v1/weather")!, 200)] {
            let client = NativeWeatherRESTClient(endpoint: endpoint, load: { [fixture] _ in
                (fixture, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!)
            })
            do { _ = try await client.fetch(NativeWeatherLocation(latitude: 0, longitude: 0)); XCTFail("Invalid HTTP response succeeded") }
            catch { XCTAssertEqual(error as? NativeWeatherIssue, .serviceUnavailable) }
        }
        XCTAssertFalse(NativeWeatherRedirectPolicy.allows(from: endpoint, to: URL(string: "https://other.example.com/v1/weather")!))
        XCTAssertFalse(NativeWeatherRedirectPolicy.allows(from: endpoint, to: URL(string: "http://weather.example.com/v1/weather")!))
    }

    func testFutureRainChanceIsNotShownAsCurrentRainChance() throws {
        let text = String(decoding: fixture, as: UTF8.self)
            .replacingOccurrences(of: "2026-10-13T04:00:00Z", with: "2026-10-13T06:00:00Z")
            .replacingOccurrences(of: "2026-10-13T05:00:00Z", with: "2026-10-13T07:00:00Z")
        let result = try NativeWeatherRESTClient.decode(Data(text.utf8))
        XCTAssertNil(result.snapshot.precipitationChance)
        XCTAssertEqual(result.snapshot.hourly?.first?.precipitationChance, 25)
    }

    func testDeterministicConditionsAndInvalidPrecipitation() throws {
        let cases: [(String, Int)] = [("Clear",0), ("MostlyClear",2), ("Cloudy",3), ("Foggy",45),
            ("Drizzle",51), ("FreezingDrizzle",56), ("Rain",61), ("HeavyRain",65), ("FreezingRain",66),
            ("Snow",71), ("HeavySnow",75), ("Hail",77), ("Thunderstorms",95), ("Windy",100),
            ("Unexpected",999), ("晴",999)]
        for (condition, code) in cases { XCTAssertEqual(NativeWeatherRESTClient.conditionCode(condition), code) }
        let text = String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "\"precipitationChance\":0.25", with: "\"precipitationChance\":25")
        XCTAssertThrowsError(try NativeWeatherRESTClient.decode(Data(text.utf8)))
    }

    func testBackendSharedAppleFixtureDecodesWithNormalizedAttribution() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = repository.appendingPathComponent("services/weather/test/fixtures")
        let weather = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("apple-weather.json")))
        let marks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("apple-attribution.json"))) as? [String: String])
        let response: [String: Any] = ["weather": weather, "attribution": [
            "combinedMarkLightURL": "https://weatherkit.apple.com" + (try XCTUnwrap(marks["logoLight@2x"])),
            "combinedMarkDarkURL": "https://weatherkit.apple.com" + (try XCTUnwrap(marks["logoDark@2x"])),
            "legalPageURL": "https://weatherkit.apple.com/legal-attribution.html"]]
        let result = try NativeWeatherRESTClient.decode(JSONSerialization.data(withJSONObject: response))
        XCTAssertEqual(result.snapshot.temperature, 22.5)
        XCTAssertEqual(result.snapshot.code, 2)
        XCTAssertEqual(result.snapshot.precipitationChance, 15)
        XCTAssertEqual(result.snapshot.low, 16)
        XCTAssertEqual(result.snapshot.high, 25)
    }
}
