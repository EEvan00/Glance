import Foundation

/// The app calls its configured HTTPS proxy. Apple signing keys stay on the server.
@MainActor
struct NativeWeatherRESTClient {
    static let maximumResponseBytes = 1_048_576
    private let endpoint: URL
    private let timeZone: @MainActor () -> String
    private let load: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(endpoint: URL, timeZone: @escaping @MainActor () -> String = { TimeZone.current.identifier },
         load: (@MainActor (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil) {
        self.endpoint = endpoint
        self.timeZone = timeZone
        self.load = load ?? { request in try await NativeWeatherTransport.load(request) }
    }

    func request(for location: NativeWeatherLocation) throws -> URLRequest {
        guard location.latitude.isFinite, location.longitude.isFinite,
              (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else { throw NativeWeatherIssue.locationUnavailable }
        guard NativeWeatherConfiguration.serviceURL(from: endpoint.absoluteString) != nil,
              var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw NativeWeatherIssue.notConfigured }
        let locale = Locale(identifier: "en_US_POSIX")
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", locale: locale, location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", locale: locale, location.longitude)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "timezone", value: timeZone())
        ]
        guard let url = parts.url else { throw NativeWeatherIssue.notConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetch(_ location: NativeWeatherLocation) async throws -> NativeWeatherResult {
        let request = try request(for: location)
        do {
            let (data, response) = try await load(request)
            try Task.checkCancellation()
            guard response.statusCode == 200, let finalURL = response.url,
                  NativeWeatherRedirectPolicy.allows(from: endpoint, to: finalURL),
                  response.mimeType?.lowercased() == "application/json" else { throw NativeWeatherIssue.serviceUnavailable }
            return try Self.decode(data)
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw NativeWeatherIssue.serviceUnavailable
        }
    }

    static func decode(_ data: Data) throws -> NativeWeatherResult {
        guard data.count <= maximumResponseBytes else { throw NativeWeatherIssue.serviceUnavailable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO8601 weather timestamp"))
            }
            return date
        }
        do {
            let response = try decoder.decode(ProxyResponse.self, from: data)
            let current = response.weather.currentWeather
            guard validTemperature(current.temperature), (0...30).contains(current.uvIndex),
                  response.weather.forecastHourly.hours.count <= 240,
                  response.weather.forecastDaily.days.count <= 14,
                  validAttribution(response.attribution.combinedMarkLightURL),
                  validAttribution(response.attribution.combinedMarkDarkURL),
                  validAttribution(response.attribution.legalPageURL) else { throw NativeWeatherIssue.serviceUnavailable }
            var snapshot = WeatherSnapshot(temperature: current.temperature, code: conditionCode(current.conditionCode),
                                           isDay: current.daylight.map { $0 ? 1 : 0 } ?? -1)
            snapshot.uvIndex = current.uvIndex
            // Ignore past hours, but retain the current forecast hour for its rain probability.
            let hours = response.weather.forecastHourly.hours.sorted { $0.forecastStart < $1.forecastStart }
                .filter { $0.forecastStart.addingTimeInterval(3600) > current.asOf }
            guard Set(hours.map(\.forecastStart)).count == hours.count else { throw NativeWeatherIssue.serviceUnavailable }
            snapshot.hourly = try hours.prefix(24).map { hour in
                guard validTemperature(hour.temperature), (0...1).contains(hour.precipitationChance) else { throw NativeWeatherIssue.serviceUnavailable }
                return WeatherHour(date: hour.forecastStart, temperature: hour.temperature, code: conditionCode(hour.conditionCode),
                                   condition: hour.conditionCode, isDay: hour.daylight.map { $0 ? 1 : 0 } ?? -1,
                                   precipitationChance: hour.precipitationChance * 100)
            }
            if let currentHour = snapshot.hourly?.first, currentHour.date <= current.asOf {
                snapshot.precipitationChance = currentHour.precipitationChance
            }
            let days = response.weather.forecastDaily.days.sorted { $0.forecastStart < $1.forecastStart }
            if let today = days.last(where: { $0.forecastStart <= current.asOf }) ?? days.first {
                guard validTemperature(today.temperatureMin), validTemperature(today.temperatureMax),
                      today.temperatureMin <= today.temperatureMax else { throw NativeWeatherIssue.serviceUnavailable }
                snapshot.low = today.temperatureMin
                snapshot.high = today.temperatureMax
                snapshot.sunrise = today.sunrise
                snapshot.sunset = today.sunset
            }
            snapshot.sunrises = days.compactMap(\.sunrise)
            snapshot.sunsets = days.compactMap(\.sunset)
            return NativeWeatherResult(snapshot: snapshot, attribution: response.attribution, updatedAt: current.asOf)
        } catch { throw NativeWeatherIssue.serviceUnavailable }
    }

    private static func validTemperature(_ value: Double) -> Bool { value.isFinite && (-150...100).contains(value) }

    private static func validAttribution(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com")
    }

    static func conditionCode(_ code: String) -> Int {
        switch code {
        case "Clear", "Hot", "Frigid": return 0
        case "MostlyClear", "PartlyCloudy": return 2
        case "MostlyCloudy", "Cloudy": return 3
        case "Foggy", "Haze", "Smoky", "BlowingDust": return 45
        case "Drizzle": return 51
        case "FreezingDrizzle": return 56
        case "Rain", "SunShowers": return 61
        case "HeavyRain": return 65
        case "FreezingRain": return 66
        case "Flurries", "Snow", "Sleet", "SunFlurries", "WintryMix", "BlowingSnow": return 71
        case "HeavySnow", "Blizzard": return 75
        case "Hail": return 77
        case "IsolatedThunderstorms", "ScatteredThunderstorms", "StrongStorms", "Thunderstorms": return 95
        case "Breezy", "Windy", "Hurricane", "TropicalStorm": return 100
        default: return 999
        }
    }
}

private struct ProxyResponse: Decodable {
    let weather: RESTWeather
    let attribution: NativeWeatherAttribution
}
private struct RESTWeather: Decodable {
    let currentWeather: RESTCurrent
    let forecastHourly: RESTHourly
    let forecastDaily: RESTDaily
}
private struct RESTCurrent: Decodable {
    let asOf: Date
    let temperature: Double
    let conditionCode: String
    let daylight: Bool?
    let uvIndex: Double
}
private struct RESTHourly: Decodable { let hours: [RESTHour] }
private struct RESTHour: Decodable {
    let forecastStart: Date
    let temperature: Double
    let conditionCode: String
    let daylight: Bool?
    let precipitationChance: Double
}
private struct RESTDaily: Decodable { let days: [RESTDay] }
private struct RESTDay: Decodable {
    let forecastStart: Date
    let temperatureMin: Double
    let temperatureMax: Double
    let sunrise: Date?
    let sunset: Date?
}

enum NativeWeatherRedirectPolicy {
    static func allows(from origin: URL, to destination: URL) -> Bool {
        destination.scheme?.lowercased() == "https" && destination.host?.lowercased() == origin.host?.lowercased() &&
        (destination.port ?? 443) == (origin.port ?? 443) && destination.user == nil && destination.password == nil
    }
}

private final class NativeWeatherRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { NativeWeatherRedirectPolicy.allows(from: origin, to: $0) } == true ? request : nil)
    }
}

private enum NativeWeatherTransport {
    static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let origin = request.url else { throw NativeWeatherIssue.notConfigured }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        let delegate = NativeWeatherRedirectDelegate(origin: origin)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= 1_048_576 else { throw NativeWeatherIssue.serviceUnavailable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw NativeWeatherIssue.serviceUnavailable }
            data.append(byte)
        }
        return (data, response)
    }
}
