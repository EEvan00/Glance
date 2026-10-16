import SwiftUI

/// Drop the update prefix before sacrificing the time or wrapping the footer.
struct WeatherUpdateTimeLabel: View {
    let fullText: String
    let timeText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(fullText).fixedSize()
            Text(timeText).fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(fullText)
        .accessibilityLabel(fullText)
    }
}
