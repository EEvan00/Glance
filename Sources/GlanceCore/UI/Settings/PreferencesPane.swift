import SwiftUI

private struct SettingsPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 150 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum SettingsPaneLayout {
    static let didChangeHeight = Notification.Name("Glance.SettingsPaneHeightChanged")
}

struct PreferencesPane<Content: View>: View {
    private let content: Content
    @State private var contentHeight: CGFloat = 150

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(width: SettingsTabViewController.contentWidth, alignment: .topLeading)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SettingsPaneHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .frame(width: SettingsTabViewController.contentWidth,
               height: min(SettingsTabViewController.maximumContentHeight, max(150, contentHeight)),
               alignment: .topLeading)
        .background(Color.clear)
        .onPreferenceChange(SettingsPaneHeightKey.self) { height in
            guard abs(contentHeight - height) > 0.5 else { return }
            contentHeight = height
            // Notify after SwiftUI has applied the new viewport height.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: SettingsPaneLayout.didChangeHeight, object: nil)
            }
        }
    }
}
