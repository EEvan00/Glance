import SwiftUI

struct CapsuleSlider<Leading: View>: View {
    @Binding var value: Double
    let label: String
    var isEnabled = true
    let onChange: (Double, Bool) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ViewBuilder let leading: () -> Leading
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = CapsuleSliderGeometry.thumbCenter(value: value, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                Capsule().fill(Color.white.opacity(isEnabled ? 0.92 : 0.35))
                    .frame(width: min(width, thumbX + 7))
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                    .offset(x: thumbX - 7)
                    .allowsHitTesting(false)
                leading()
                    .foregroundStyle(Color.black.opacity(0.65))
                    .font(.system(size: 14))
                    .frame(width: 14, height: 14)
            }
            .contentShape(Capsule())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard isEnabled else { return }
                if !isDragging { onEditingChanged(true) }
                isDragging = true
                set(CapsuleSliderGeometry.value(at: gesture.location.x, width: width), final: false)
            }.onEnded { gesture in
                guard isDragging else { return }
                isDragging = false
                set(CapsuleSliderGeometry.value(at: gesture.location.x, width: width), final: true)
                onEditingChanged(false)
            })
        }
        .frame(height: 14)
        .overlay {
            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7).allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value.isFinite ? min(1, max(0, value)) : 0) * 100))%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: set(value + 0.05, final: true)
            case .decrement: set(value - 0.05, final: true)
            @unknown default: break
            }
        }
        .focusable(isEnabled)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { guard isEnabled else { return .ignored }; set(value - 0.05, final: true); return .handled }
        .onKeyPress(.rightArrow) { guard isEnabled else { return .ignored }; set(value + 0.05, final: true); return .handled }
        .opacity(isEnabled ? 1 : 0.55)
        .help("\(label) · \(Int((value.isFinite ? min(1, max(0, value)) : 0) * 100))%")
    }

    private func set(_ scalar: Double, final: Bool) {
        guard scalar.isFinite else { return }
        value = min(1, max(0, scalar))
        onChange(value, final)
    }
}
