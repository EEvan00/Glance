import Foundation

struct CountdownIndicator: Equatable, Sendable {
    let progress: Double
    let number: Int
    let isDimmed: Bool

    init(remaining: TimeInterval, duration: TimeInterval, isDimmed: Bool = false) {
        progress = duration > 0 ? min(1, max(0, remaining / duration)) : 0
        number = remaining >= 60 ? Int(ceil(remaining / 60)) : min(59, max(0, Int(ceil(remaining))))
        self.isDimmed = isDimmed
    }
}
