import Foundation

struct WeatherSnapshot: Decodable, Equatable, Sendable {
    let temperature: Double
    let code: Int
    let isDay: Int
    var shortcutVersion: Int? = nil
    var appleCondition: String? = nil
    var low: Double? = nil
    var high: Double? = nil
    var location: String? = nil
    var hourly: [WeatherHour]? = nil
    var uvIndex: Double? = nil
    var precipitationChance: Double? = nil
    var sunrise: Date? = nil
    var sunset: Date? = nil
    var sunrises: [Date]? = nil
    var sunsets: [Date]? = nil

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case code = "weather_code"
        case isDay = "is_day"
        case shortcutVersion, appleCondition, low, high, hourly, location, uvIndex, precipitationChance, sunrise, sunset, sunrises, sunsets
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
        let code = Self.conditionCode(condition)
        var snapshot = WeatherSnapshot(temperature: temperature, code: code, isDay: -1, appleCondition: condition)
        snapshot.readForecast(lines: Array(lines.dropFirst(2)))
        return snapshot
    }

    // Shortcuts return conditions in the system language, independently of the app language.
    static func conditionCode(_ condition: String) -> Int {
        let value = condition.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let groups: [(Int, [String])] = [
            (95, ["thunder", "雷", "천둥", "뇌우", "tormenta", "orage", "gewitter", "temporale", "trovo", "гроза", "رعد"]),
            (71, ["snow", "sleet", "雪", "눈", "nieve", "neige", "schnee", "neve", "снег", "ثلج"]),
            (51, ["drizzle", "毛毛雨", "細雨", "细雨", "霧雨", "이슬비", "llovizna", "bruine", "niesel", "pioviggine", "garoa", "морось", "رذاذ"]),
            (61, ["rain", "shower", "雨", "비", "lluvia", "chubasco", "pluie", "averse", "regen", "pioggia", "chuva", "дожд", "مطر"]),
            (45, ["fog", "haze", "mist", "雾", "霧", "안개", "niebla", "brouillard", "nebel", "nebbia", "nevoeiro", "туман", "ضباب"]),
            (100, ["wind", "breez", "风", "風", "바람", "viento", "vent", "vento", "ветер", "ветр", "رياح"]),
            (2, ["partly", "mostly sunny", "晴间", "晴間", "晴れ時々", "구름 조금", "parcialmente", "partiellement", "teilweise", "parzialmente", "переменная", "غائم جزئيا"]),
            (3, ["cloud", "overcast", "云", "雲", "阴", "陰", "曇", "구름", "흐림", "nublado", "nuboso", "nuage", "bewolkt", "nuvoloso", "облач", "غائم"]),
            (0, ["clear", "sunny", "晴", "맑", "despejado", "degagé", "degage", "klar", "sereno", "limpo", "ясно", "صافي"])
        ]
        return groups.first { group in group.1.contains { value.contains($0) } }?.0 ?? 999
    }

    var symbol: String {
        switch code {
        case 0: return isDay == 0 ? "moon.fill" : "sun.max.fill"
        case 1, 2: return isDay == 0 ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        case 100: return "wind"
        default: return "questionmark"
        }
    }

    var conditionKey: LocalizationKey {
        switch code {
        case 0: return .weatherClear
        case 1, 2: return .weatherPartlyCloudy
        case 3: return .weatherCloudy
        case 45, 48: return .weatherFog
        case 51...57: return .weatherDrizzle
        case 61...67, 80...82: return .weatherRain
        case 71...77, 85, 86: return .weatherSnow
        case 95...99: return .weatherThunderstorm
        case 100: return .weatherWind
        default: return .weatherUnknown
        }
    }

    var forecastEntries: [WeatherForecastEntry] {
        let hours = hourly ?? []
        guard let first = hours.first, let last = hours.last else { return [] }
        var entries = hours.map { WeatherForecastEntry.hour($0) }
        let end = last.date.addingTimeInterval(3600)
        for date in sunrises ?? sunrise.map({ [$0] }) ?? [] where date >= first.date && date < end {
            entries.append(.sunrise(date))
        }
        for date in sunsets ?? sunset.map({ [$0] }) ?? [] where date >= first.date && date < end {
            entries.append(.sunset(date))
        }
        return entries.sorted { $0.date < $1.date }
    }

    var temperatureText: String {
        TemperatureUnit.celsius.text(celsius: temperature)
    }
}

struct WeatherHour: Decodable, Equatable, Sendable, Identifiable {
    let date: Date
    let temperature: Double
    let code: Int
    let condition: String
    var isDay: Int = -1
    var precipitationChance: Double? = nil
    var id: Date { date }
    var symbol: String {
        if code == 0 {
            let daytime = isDay == -1 ? (6..<18).contains(Calendar.current.component(.hour, from: date)) : isDay == 1
            return daytime ? "sun.max.fill" : "moon.fill"
        }
        if isDay == -1, (0...2).contains(code) { return "cloud.fill" }
        return WeatherSnapshot(temperature: temperature, code: code, isDay: isDay).symbol
    }
    var temperatureText: String { WeatherSnapshot(temperature: temperature, code: code, isDay: -1).temperatureText }
}

enum WeatherForecastEntry: Equatable, Sendable, Identifiable {
    case hour(WeatherHour)
    case sunrise(Date)
    case sunset(Date)

    var date: Date {
        switch self {
        case .hour(let hour): hour.date
        case .sunrise(let date), .sunset(let date): date
        }
    }

    var id: String {
        let kind: String
        switch self {
        case .hour: kind = "hour"
        case .sunrise: kind = "sunrise"
        case .sunset: kind = "sunset"
        }
        return "\(kind)-\(date.timeIntervalSince1970)"
    }
}

private extension WeatherSnapshot {
    static func parsePrecipitationChance(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "％", with: "%")
        guard let value = Double(normalized.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        let percent = !normalized.contains("%") && (0...1).contains(value) ? value * 100 : value
        return (0...100).contains(percent) ? percent : nil
    }

    mutating func readForecast(lines: [String]) {
        guard !lines.isEmpty, lines.count <= 200 else { return }
        let markers: Set<String> = ["LOW", "HIGH", "DATES", "HOURS", "LOCATION", "UV", "SUNRISE", "SUNSET", "RAIN_CHANCES", "RAIN_CHANCE", "GLANCE_VERSION"]
        var sections: [String: [String]] = [:]
        var current: String?
        for line in lines {
            if markers.contains(line) { current = line; sections[line] = [] }
            else if let current { sections[current, default: []].append(line) }
        }
        if let values = sections["GLANCE_VERSION"], values.count == 1,
           let version = Int(values[0]), version > 0 { shortcutVersion = version }
        if let values = sections["UV"], values.count == 1,
           let value = Double(values[0].replacingOccurrences(of: ",", with: ".")),
           value.isFinite, (0...30).contains(value) { uvIndex = value }
        if let values = sections["RAIN_CHANCE"], values.count == 1 {
            precipitationChance = Self.parsePrecipitationChance(values[0])
        }
        let solarFormatter = ISO8601DateFormatter()
        sunrises = sections["SUNRISE"].map { $0.compactMap { solarFormatter.date(from: $0) } }
        sunsets = sections["SUNSET"].map { $0.compactMap { solarFormatter.date(from: $0) } }
        sunrise = sunrises?.first
        sunset = sunsets?.first
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
        for (index, pair) in zip(dates, conditions).enumerated() {
            let (dateText, conditionText) = pair
            guard let date = formatter.date(from: dateText) ?? fractional.date(from: dateText),
                  let match = expression.firstMatch(in: conditionText, range: NSRange(conditionText.startIndex..., in: conditionText)),
                  let range = Range(match.range, in: conditionText),
                  let weather = Self.fromShortcut(String(conditionText[range]) + "\n" + conditionText),
                  entries.last.map({ date > $0.date }) ?? true else { return }
            let daylight: Int
            if let solarDay = zip(sections["SUNRISE"] ?? [], sections["SUNSET"] ?? [])
                .first(where: { $0.0.prefix(10) == dateText.prefix(10) && $0.1.prefix(10) == dateText.prefix(10) }),
               let sunrise = solarFormatter.date(from: solarDay.0),
               let sunset = solarFormatter.date(from: solarDay.1), sunrise < sunset {
                daylight = date >= sunrise && date < sunset ? 1 : 0
            } else {
                daylight = -1
            }
            let probability: Double?
            if let values = sections["RAIN_CHANCES"], values.count == dates.count {
                probability = Self.parsePrecipitationChance(values[index])
            } else { probability = nil }
            entries.append(WeatherHour(date: date, temperature: weather.temperature, code: weather.code,
                                      condition: weather.appleCondition ?? conditionText, isDay: daylight,
                                      precipitationChance: probability))
        }
        hourly = Array(entries.prefix(24))
    }
}
