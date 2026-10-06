import AppKit
import XCTest
@testable import GlanceCore

final class FooterClockFormattingTests: XCTestCase {
    func testTwelveHourClockOmitsAmPm() {
        let zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(FooterClockFormatting.time(Date(timeIntervalSince1970: 0), uses24HourClock: false, timeZone: zone), "12:00")
        XCTAssertEqual(FooterClockFormatting.time(Date(timeIntervalSince1970: 43200), uses24HourClock: false, timeZone: zone), "12:00")
        XCTAssertEqual(FooterClockFormatting.time(Date(timeIntervalSince1970: 43200), uses24HourClock: true, timeZone: zone), "12:00")
    }

    func testWeekdayMatchesDateInSelectedTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        let zone = TimeZone(secondsFromGMT: -3600)!
        XCTAssertEqual(FooterClockFormatting.date(date, locale: Locale(identifier: "zh_CN"), chinese: true, timeZone: zone), "31 周三")
        XCTAssertEqual(FooterClockFormatting.date(date, locale: Locale(identifier: "en_US"), chinese: false, timeZone: zone), "31 Wed")
    }
    @MainActor func testGridDateAndCompactStatesFitAllLanguages() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let localization = Localization(defaults: defaults)
        let stateKeys: [LocalizationKey] = [.compactUnavailable, .compactCharged, .compactCharging, .compactLowPower,
            .compactPower, .compactOnBattery, .compactConnected, .compactDisconnected, .compactOff,
            .compactNoInternet, .compactHotspot, .compactTemporary, .compactShared, .compactLoading,
            .compactNoAccess, .compactCached, .compactNoData, .timerPaused]
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        for language in AppLanguage.allCases {
            for key in stateKeys {
                let text = localization.string(key, language: language)
                let width = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10)]).size().width
                XCTAssertLessThanOrEqual(width, 86, "\(language.rawValue) \(text)")
            }
            let title = localization.string(.compactBattery, language: language) + " · 100%"
            let titleWidth = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
            XCTAssertLessThanOrEqual(titleWidth * 0.85, 86, language.rawValue)
            for day in 0..<365 {
                let date = calendar.date(byAdding: .day, value: day, to: first)!
                let text = FooterClockFormatting.date(date, locale: language.locale, chinese: language.isChinese, timeZone: zone)
                let width = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]).size().width
                XCTAssertLessThanOrEqual(width, CompactPopupLayout.span(2), "\(language.rawValue) \(text)")
            }
        }
        XCTAssertEqual(CompactPopupLayout.span(1), 24)
        XCTAssertEqual(CompactPopupLayout.span(2), 52)
        XCTAssertEqual(CompactPopupLayout.span(5), 136)
        let spans = [1, 1, 2, 2, 2, 1, 1]
        XCTAssertEqual(spans.reduce(CGFloat(0)) { $0 + CompactPopupLayout.span($1) } + 6 * CompactPopupLayout.gap, 276)
    }

    func testOptionalSecondsAndTheirGridWidth() {
        let date = Date(timeIntervalSince1970: 86399)
        let fractional = Date(timeIntervalSince1970: 86399.45)
        XCTAssertEqual(FooterClockFormatting.timelineStart(showsSeconds: false, now: fractional).timeIntervalSince1970, 86340)
        XCTAssertEqual(FooterClockFormatting.timelineStart(showsSeconds: true, now: fractional).timeIntervalSince1970, 86399)
        let zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(FooterClockFormatting.time(date, uses24HourClock: true, showsSeconds: true, timeZone: zone), "23:59:59")
        XCTAssertEqual(FooterClockFormatting.time(date, uses24HourClock: false, showsSeconds: true, timeZone: zone), "11:59:59")
        XCTAssertEqual(FooterClockFormatting.time(date, uses24HourClock: true, timeZone: zone), "23:59")
        let width = NSAttributedString(string: "23:59:59", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]).size().width
        XCTAssertLessThanOrEqual(width, CompactPopupLayout.span(2))
    }

}
