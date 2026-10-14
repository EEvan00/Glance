import SwiftUI

/// Apple's combined mark and legal URL are supplied dynamically with native data.
struct WeatherAttributionView: View {
    let attribution: NativeWeatherAttribution
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var localization: Localization

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: attribution.markURL(for: colorScheme)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(localization.string(.weatherAttribution)).font(.caption)
            }
            .frame(width: 110, height: 20)
            .accessibilityLabel(localization.string(.weatherAttribution))
            Spacer(minLength: 4)
            Link(localization.string(.weatherLegal), destination: attribution.legalPageURL)
                .font(.caption)
        }
    }
}
