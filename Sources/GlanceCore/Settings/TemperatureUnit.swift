import Foundation

/// Weather snapshots always store Celsius; units are applied only for display.
enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    func text(celsius: Double, includesUnit: Bool = false) -> String {
        guard celsius.isFinite, abs(celsius) < 1000 else { return "—" }
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))\(includesUnit ? symbol : "°")"
    }
}
