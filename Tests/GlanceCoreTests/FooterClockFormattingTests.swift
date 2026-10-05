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
        XCTAssertEqual(FooterClockFormatting.date(date, locale: Locale(identifier: "zh_CN"), chinese: true, timeZone: zone), "31/Dec 周三")
        XCTAssertEqual(FooterClockFormatting.date(date, locale: Locale(identifier: "en_US"), chinese: false, timeZone: zone), "31/Dec Wed")
    }
}
