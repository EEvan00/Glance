import Foundation

enum CapsuleSliderGeometry {
    static func thumbCenter(value: Double, width: Double) -> Double {
        let scalar = value.isFinite ? min(1, max(0, value)) : 0
        return 7 + scalar * max(1, width - 14)
    }

    static func value(at x: Double, width: Double) -> Double {
        guard x.isFinite, width.isFinite else { return 0 }
        return min(1, max(0, (x - 7) / max(1, width - 14)))
    }
}
