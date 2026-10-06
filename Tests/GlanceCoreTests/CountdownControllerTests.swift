import XCTest
@testable import GlanceCore

final class CountdownControllerTests: XCTestCase {
    @MainActor func testPauseResumeAndFinishesExactlyOnce() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var now = Date(timeIntervalSince1970: 1000)
        let timer = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        var completions = 0
        timer.onFinish = { completions += 1 }
        timer.start(minutes: 1)
        now = now.addingTimeInterval(20)
        timer.pause()
        XCTAssertEqual(timer.remaining, 40)
        now = now.addingTimeInterval(100)
        timer.tick()
        XCTAssertEqual(timer.remaining, 40)
        timer.resume()
        now = now.addingTimeInterval(41)
        timer.tick()
        timer.tick()
        XCTAssertTrue(timer.isFinished)
        XCTAssertEqual(completions, 1)
        timer.cancel()
        XCTAssertFalse(timer.isFinished)
        XCTAssertNil(defaults.dictionary(forKey: "countdownState"))
    }

    @MainActor func testRestoresAbsoluteDeadlineAndPausedState() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var now = Date(timeIntervalSince1970: 1000)
        let original = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        original.start(minutes: 5)
        now = now.addingTimeInterval(120)
        let restored = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        XCTAssertEqual(restored.remaining, 180)
        restored.pause()
        now = now.addingTimeInterval(500)
        let paused = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.remaining, 180)
    }

    @MainActor func testExpiredDeadlineAfterRestartFinishesAndInvalidDurationIsIgnored() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var now = Date(timeIntervalSince1970: 1000)
        let original = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        original.start(minutes: 0)
        XCTAssertFalse(original.isRunning)
        original.start(minutes: 1)
        now = now.addingTimeInterval(120)
        let restored = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        restored.tick()
        XCTAssertTrue(restored.isFinished)
        XCTAssertEqual(CountdownController.display(59.2), "01:00")
        XCTAssertEqual(CountdownController.display(3601), "1:00:01")
    }
    func testMenuBarNumberUsesMinutesThenSecondsWithoutUnits() {
        XCTAssertEqual(CountdownIndicator(remaining: 1500, duration: 1500).number, 25)
        XCTAssertEqual(CountdownIndicator(remaining: 60.1, duration: 1500).number, 2)
        XCTAssertEqual(CountdownIndicator(remaining: 60, duration: 1500).number, 1)
        XCTAssertEqual(CountdownIndicator(remaining: 59.1, duration: 1500).number, 59)
        XCTAssertEqual(CountdownIndicator(remaining: 59, duration: 1500).number, 59)
        XCTAssertEqual(CountdownIndicator(remaining: 0, duration: 1500).number, 0)
        XCTAssertEqual(CountdownIndicator(remaining: 750, duration: 1500).progress, 0.5)
    }

    @MainActor func testFinishBlinksForFiveSecondsThenClearsState() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var now = Date(timeIntervalSince1970: 1000)
        let timer = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        timer.start(minutes: 1)
        now = now.addingTimeInterval(60)
        timer.tick()
        XCTAssertEqual(timer.indicator?.isDimmed, true)
        now = now.addingTimeInterval(0.25)
        timer.tick()
        XCTAssertEqual(timer.indicator?.isDimmed, false)
        now = now.addingTimeInterval(0.25)
        timer.tick()
        XCTAssertEqual(timer.indicator?.isDimmed, true)
        now = now.addingTimeInterval(4.49)
        timer.tick()
        XCTAssertNotNil(timer.indicator)
        now = now.addingTimeInterval(0.01)
        timer.tick()
        XCTAssertFalse(timer.isFinished)
        XCTAssertNil(timer.indicator)
        XCTAssertNil(defaults.dictionary(forKey: "countdownState"))
    }

    @MainActor func testStartPauseResumeAndCancelRescheduleNotificationDeadline() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 1000)
        let timer = CountdownController(defaults: defaults, now: { now }, automaticTicks: false)
        var deadlines: [Date?] = []
        timer.onSchedule = { deadlines.append($0) }
        timer.start(minutes: 5)
        timer.pause()
        timer.resume()
        timer.cancel()
        XCTAssertEqual(deadlines, [now.addingTimeInterval(300), nil, now.addingTimeInterval(300), nil])
    }

}
