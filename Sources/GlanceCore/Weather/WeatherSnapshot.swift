import Foundation

struct WeatherSnapshot: Decodable, Equatable, Sendable {
    let temperature: Double
    let code: Int
    let isDay: Int
    var appleCondition: String? = nil
    var low: Double? = nil
    var high: Double? = nil
    var location: String? = nil
    var hourly: [WeatherHour]? = nil

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case code = "weather_code"
        case isDay = "is_day"
        case appleCondition, low, high, hourly, location
    }

    static func fromShortcut(_ output: String) -> WeatherSnapshot? {
        let lines = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count >= 2, let first = lines.first,
              let expression = try? NSRegularExpression(pattern: #"^([-+]?[0-9]+(?:[.,][0-9]+)?)\s*[°º]\s*([CF])$"#, options: .caseInsensitive),
              let match = expression.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)),
              let scalarRange = Range(match.range(at: 1), in: first), let unitRange = Range(match.range(at: 2), in: first),
              let scalar = Double(first[scalarRange].replacingOccurrences(of: ",", with: ".")), scalar.isFinite else { return nil }
        let temperature = first[unitRange].uppercased() == "F" ? (scalar - 32) * 5 / 9 : scalar
        guard (-150...100).contains(temperature) else { return nil }
        var condition = lines[1]
        if condition.hasPrefix(first) {
            condition = String(condition.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if condition.lowercased().hasPrefix("and ") { condition = String(condition.dropFirst(4)) }
            condition = condition.trimmingCharacters(in: CharacterSet(charactersIn: " ,，和且"))
        }
        guard !condition.isEmpty, condition.count <= 160 else { return nil }
        let value = condition.lowercased()
        let code: Int
        if value.contains("thunder") || value.contains("雷") { code = 95 }
        else if value.contains("snow") || value.contains("sleet") || value.contains("雪") { code = 71 }
        else if value.contains("rain") || value.contains("drizzle") || value.contains("shower") || value.contains("雨") { code = 61 }
        else if value.contains("fog") || value.contains("haze") || value.contains("mist") || value.contains("雾") || value.contains("霧") { code = 45 }
        else if value.contains("partly") || value.contains("mostly clear") || value.contains("mostly sunny") || value.contains("晴间") { code = 2 }
        else if value.contains("cloud") || value.contains("overcast") || value.contains("云") || value.contains("雲") || value.contains("阴") || value.contains("陰") { code = 3 }
        else if value.contains("clear") || value.contains("sunny") || value == "晴" { code = 0 }
        else { code = 999 }
        var snapshot = WeatherSnapshot(temperature: temperature, code: code, isDay: -1, appleCondition: condition)
        snapshot.readForecast(lines: Array(lines.dropFirst(2)))
        return snapshot
    }

    var symbol: String {
        switch code {
        case 0: return isDay == -1 ? "thermometer.medium" : (isDay == 1 ? "sun.max.fill" : "moon.fill")
        case 1, 2: return isDay == -1 ? "cloud.fill" : (isDay == 1 ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "questionmark"
        }
    }

    var conditionKey: LocalizationKey {
        switch code {
        case 0: return .weatherClear
        case 1, 2: return .weatherPartlyCloudy
        case 3: return .weatherCloudy
        case 45, 48: return .weatherFog
        case 51...67, 80...82: return .weatherRain
        case 71...77, 85, 86: return .weatherSnow
        case 95...99: return .weatherThunderstorm
        default: return .weatherUnknown
        }
    }

    var temperatureText: String {
        temperature.isFinite && abs(temperature) < 1000 ? "\(Int(temperature.rounded()))°" : "—"
    }
}

struct WeatherHour: Decodable, Equatable, Sendable, Identifiable {
    let date: Date
    let temperature: Double
    let code: Int
    let condition: String
    var id: Date { date }
    var symbol: String { WeatherSnapshot(temperature: temperature, code: code, isDay: -1).symbol }
    var temperatureText: String { WeatherSnapshot(temperature: temperature, code: code, isDay: -1).temperatureText }
}

private extension WeatherSnapshot {
    mutating func readForecast(lines: [String]) {
        guard !lines.isEmpty, lines.count <= 120 else { return }
        let markers: Set<String> = ["LOW", "HIGH", "DATES", "HOURS", "LOCATION"]
        var sections: [String: [String]] = [:]
        var current: String?
        for line in lines {
            if markers.contains(line) { current = line; sections[line] = [] }
            else if let current { sections[current, default: []].append(line) }
        }
        if let city = sections["LOCATION"], city.count == 1, city[0].count <= 80,
           !city[0].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            location = city[0]
        }
        if let lowText = sections["LOW"], lowText.count == 1,
           let highText = sections["HIGH"], highText.count == 1,
           let minimum = Self.fromShortcut(lowText[0] + "\nUnknown")?.temperature,
           let maximum = Self.fromShortcut(highText[0] + "\nUnknown")?.temperature,
           minimum <= maximum {
            low = minimum; high = maximum
        }
        guard let dates = sections["DATES"], let conditions = sections["HOURS"],
              dates.count == conditions.count, !dates.isEmpty, dates.count <= 48 else { return }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let expression = try? NSRegularExpression(pattern: #"^[-+]?[0-9]+(?:[.,][0-9]+)?\s*[°º]\s*[CF]"#, options: .caseInsensitive) else { return }
        var entries: [WeatherHour] = []
        for (dateText, conditionText) in zip(dates, conditions) {
            guard let date = formatter.date(from: dateText) ?? fractional.date(from: dateText),
                  let match = expression.firstMatch(in: conditionText, range: NSRange(conditionText.startIndex..., in: conditionText)),
                  let range = Range(match.range, in: conditionText),
                  let weather = Self.fromShortcut(String(conditionText[range]) + "\n" + conditionText),
                  entries.last.map({ date > $0.date }) ?? true else { return }
            entries.append(WeatherHour(date: date, temperature: weather.temperature, code: weather.code, condition: weather.appleCondition ?? conditionText))
        }
        hourly = Array(entries.prefix(24))
    }
}
