import SwiftUI

struct BrightnessControlsView: View {
    @ObservedObject var controller: BrightnessController
    var onOpenDisplay: (() -> Void)? = nil
    @EnvironmentObject private var localization: Localization
    @State private var isAdjusting = false
    @State private var value = 0.0

    var body: some View {
        if controller.value != nil {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill").font(.system(size: 14)).frame(width: 22, height: 24)
                CapsuleSlider(value: $value, label: localization.string(.brightnessTitle), onChange: { scalar, final in
                    controller.setValue(scalar, final: final)
                }, onEditingChanged: { isAdjusting = $0 }) { EmptyView() }
                if let onOpenDisplay {
                    Button(action: onOpenDisplay) { PopupChevron() }
                        .buttonStyle(.plain).accessibilityLabel(localization.string(.displayTitle))
                }
            }
            .onAppear { value = controller.value ?? 0 }
            .onChange(of: controller.value) { _, scalar in if !isAdjusting { value = scalar ?? 0 } }
        }
    }
}
