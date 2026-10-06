import Foundation

enum FooterClockFormatting {
    static func date(_ date: Date, locale: Locale, chinese: Bool, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d"
        let text = formatter.string(from: date)
        guard chinese else {
            formatter.locale = locale
            formatter.dateFormat = "EEE"
            return text + " " + formatter.string(from: date)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.component(.weekday, from: date)
        return text + " 周" + ["日", "一", "二", "三", "四", "五", "六"][day - 1]
    }

    static func timelineStart(showsSeconds: Bool, now: Date = Date()) -> Date {
        let interval: TimeInterval = showsSeconds ? 1 : 60
        return Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / interval) * interval)
    }

    static func time(_ date: Date, uses24HourClock: Bool, showsSeconds: Bool = false, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = (uses24HourClock ? "HH:mm" : "h:mm") + (showsSeconds ? ":ss" : "")
        return formatter.string(from: date).lowercased()
    }
}
