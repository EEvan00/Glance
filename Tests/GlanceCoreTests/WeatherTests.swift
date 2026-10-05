import AppKit
import XCTest
@testable import GlanceCore

final class WeatherTests: XCTestCase {
    @MainActor
    func testWeatherCacheAvoidsRequestsForEmptyShortcutAndFreshData() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(WeatherController.shouldRefresh(shortcutName: "  ", lastAttempt: nil, now: now))
        XCTAssertFalse(WeatherController.shouldRefresh(shortcutName: "Sydney", lastAttempt: now.addingTimeInterval(-899), now: now))
        XCTAssertTrue(WeatherController.shouldRefresh(shortcutName: "Sydney", lastAttempt: now.addingTimeInterval(-900), now: now))
        XCTAssertTrue(WeatherController.shouldRefresh(shortcutName: "Sydney", lastAttempt: nil, now: now))
    }

    @MainActor
    func testBuiltInWeatherNameIgnoresLegacyStoredName() {
        let name = "Glance.Weather.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Status Trio Weather", forKey: "weatherShortcutName")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.weatherShortcutName, "Glance Weather")
        XCTAssertEqual(settings.weatherForecastShortcutName, "Glance Weather Forecast")
    }

    @MainActor
    func testShortcutProcessLoadsWeatherAndClearsItOnFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("weather")
        try "#!/bin/sh\nif [ \"$2\" = \"fail\" ]; then exit 1; fi\ncat > /dev/null\nprintf '18°C\\n18°C and Cloudy\\n' > \"$6\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let controller = WeatherController(executable: executable)
        controller.setVisible(true, shortcutName: "good")
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(controller.isLoading)
        XCTAssertEqual(controller.snapshot?.appleCondition, "Cloudy")
        XCTAssertNotNil(controller.updatedAt)
        try "#!/bin/sh\nif [ \"$2\" = \"fail\" ]; then exit 1; fi\ncat > /dev/null\nprintf '19°C\\nRain\\nUV\\n2\\n' > \"$6\"\n".write(to: executable, atomically: true, encoding: .utf8)
        controller.setVisible(true, shortcutName: "good")
        XCTAssertFalse(controller.isLoading)
        XCTAssertEqual(controller.snapshot?.temperature, 18)
        controller.refreshNow(shortcutName: "good")
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(controller.snapshot?.temperature, 19)
        XCTAssertEqual(controller.snapshot?.uvIndex, 2)
        controller.setVisible(true, shortcutName: "fail")
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(controller.snapshot)
        XCTAssertNil(controller.updatedAt)
        XCTAssertTrue(controller.isUnavailable)
        controller.setVisible(false, shortcutName: "fail")
        // A failed fetch must be retryable on the next opening, without a 15-minute wait.
        try "#!/bin/sh\ncat > /dev/null\nprintf '19°C\\nRain\\n' > \"$6\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        controller.setVisible(true, shortcutName: "fail")
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(controller.snapshot?.temperature, 19)
        XCTAssertFalse(controller.isUnavailable)
        controller.setVisible(false, shortcutName: "fail")
    }

    func testShortcutOutputConvertsFahrenheitAndExtractsCondition() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("64.4°F\n64.4°F and Cloudy"))
        XCTAssertEqual(value.temperature, 18, accuracy: 0.001)
        XCTAssertEqual(value.appleCondition, "Cloudy")
        XCTAssertEqual(value.symbol, "cloud.fill")
        XCTAssertNil(WeatherSnapshot.fromShortcut("not a temperature\nClear"))
        XCTAssertNil(WeatherSnapshot.fromShortcut("1000°C\nClear"))
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C"))
    }

    func testShortcutConditionChangesIconAndPreservesUnknownText() throws {
        XCTAssertEqual(WeatherSnapshot.fromShortcut("18°C\nClear")?.symbol, "sun.max.fill")
        XCTAssertEqual(WeatherSnapshot.fromShortcut("18°C\nLight Rain")?.symbol, "cloud.rain.fill")
        XCTAssertEqual(WeatherSnapshot.fromShortcut("-2°C\n雪")?.symbol, "cloud.snow.fill")
        let unknown = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nUnexpected Condition"))
        XCTAssertEqual(unknown.appleCondition, "Unexpected Condition")
        XCTAssertEqual(unknown.symbol, "questionmark")
    }

    func testForecastParsesDailyRangeAndPairsHourlyDatesWithConditions() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nCloudy\nLOW\n12°C\nHIGH\n23°C\nDATES\n2026-10-05T23:00:00+11:00\n2026-10-06T00:00:00+11:00\nHOURS\n18°C and Drizzle\n17°C and Cloudy"))
        XCTAssertEqual(value.low, 12)
        XCTAssertEqual(value.high, 23)
        XCTAssertEqual(value.hourly?.count, 2)
        XCTAssertEqual(value.hourly?.first?.temperature, 18)
        XCTAssertEqual(value.hourly?.first?.symbol, "cloud.rain.fill")
        XCTAssertEqual(value.hourly?.last?.condition, "Cloudy")
    }

    func testLocationParsesWithoutForecastAndRejectsMultipleLines() throws {
        XCTAssertEqual(WeatherSnapshot.fromShortcut("18°C\nCloudy\nLOCATION\nSydney")?.location, "Sydney")
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C\nCloudy\nLOCATION\nSydney\nExtra")?.location)
    }

    @MainActor
    func testBundledWeatherShortcutsAreAvailable() throws {
        for shortcut in BundledWeatherShortcut.allCases {
            let url = try XCTUnwrap(shortcut.url)
            XCTAssertEqual(url.pathExtension, "shortcut")
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 1000)
        }
    }

    func testMalformedForecastDoesNotHideCurrentWeatherOrPairWrongHours() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nCloudy\nLOW\n25°C\nHIGH\n12°C\nDATES\n2026-10-05T23:00:00+11:00\nHOURS\n18°C and Rain\n17°C and Cloudy"))
        XCTAssertEqual(value.temperature, 18)
        XCTAssertNil(value.low)
        XCTAssertNil(value.high)
        XCTAssertTrue(value.hourly?.isEmpty ?? true)
    }

    func testCurrentWeatherDecodingAndNightSymbol() throws {
        let value = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(#"{"temperature_2m":-2.6,"weather_code":0,"is_day":0}"#.utf8))
        XCTAssertEqual(value.temperatureText, "-3°")
        XCTAssertEqual(value.symbol, "moon.fill")
    }

    func testWindAndClearConditionsUseWeatherSymbols() throws {
        XCTAssertEqual(WeatherSnapshot.fromShortcut("18°C\nWindy")?.symbol, "wind")
        XCTAssertEqual(WeatherSnapshot.fromShortcut("18°C\nMostly Clear")?.symbol, "sun.max.fill")
    }

    func testExtendedWeatherDetailsAreOptionalAndValidated() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nCloudy\nUV\n3\nSUNRISE\n2026-10-06T06:25:00+11:00\nSUNSET\n2026-10-06T19:04:00+11:00"))
        XCTAssertEqual(value.uvIndex, 3)
        XCTAssertNotNil(value.sunrise)
        XCTAssertNotNil(value.sunset)
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C\nCloudy\nUV\n-1")?.uvIndex)
    }

    func testHourlyClearAfterSunsetUsesMoonInsteadOfSun() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nCloudy\nSUNRISE\n2026-10-06T06:25:00+11:00\nSUNSET\n2026-10-06T19:04:00+11:00\nDATES\n2026-10-06T12:00:00+11:00\n2026-10-06T20:00:00+11:00\nHOURS\n18°C and Clear\n17°C and Mostly Clear"))
        XCTAssertEqual(value.hourly?.first?.symbol, "sun.max.fill")
        XCTAssertEqual(value.hourly?.last?.symbol, "moon.fill")
    }

    func testSolarEventsAreInsertedChronologicallyIntoHourlyForecast() throws {
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nClear\nSUNRISE\n2026-10-06T06:25:00+11:00\nSUNSET\n2026-10-06T19:04:00+11:00\nDATES\n2026-10-06T06:00:00+11:00\n2026-10-06T19:00:00+11:00\nHOURS\n18°C and Mostly Clear\n17°C and Clear"))
        XCTAssertEqual(value.forecastEntries.count, 4)
        XCTAssertEqual(value.forecastEntries.map(\.date), value.forecastEntries.map(\.date).sorted())
        XCTAssertEqual(Set(value.forecastEntries.map(\.id)).count, 4)
    }

    func testHourlyRainChanceMatchesHoursAndDoesNotInventMissingValues() throws {
        let base = "18°C\nCloudy\nDATES\n2026-10-06T06:00:00+11:00\n2026-10-06T07:00:00+11:00\nHOURS\n18°C and Rain\n17°C and Cloudy\nRAIN_CHANCES\n"
        let value = try XCTUnwrap(WeatherSnapshot.fromShortcut(base + "80%\n0.25"))
        XCTAssertEqual(value.hourly?.first?.precipitationChance, 80)
        XCTAssertEqual(value.hourly?.last?.precipitationChance, 25)
        let mismatched = try XCTUnwrap(WeatherSnapshot.fromShortcut(base + "80%"))
        XCTAssertNil(mismatched.hourly?.first?.precipitationChance)
        XCTAssertEqual(mismatched.hourly?.count, 2)
        let invalid = try XCTUnwrap(WeatherSnapshot.fromShortcut(base + "101%\n-5%"))
        XCTAssertNil(invalid.hourly?.first?.precipitationChance)
        XCTAssertNil(invalid.hourly?.last?.precipitationChance)
    }

    func testUnknownWeatherDoesNotPretendToBeSunny() throws {
        let value = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(#"{"temperature_2m":20,"weather_code":999,"is_day":1}"#.utf8))
        XCTAssertEqual(value.symbol, "questionmark")
    }
}
