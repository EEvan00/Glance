import AppKit
import SwiftUI

struct NowPlayingArtworkView: View {
    let data: Data?
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08))
                    .overlay { Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
        .onAppear { image = data.flatMap(NSImage.init(data:)) }
        .onChange(of: data) { _, data in image = data.flatMap(NSImage.init(data:)) }
    }
}

struct NowPlayingSourceIconView: View {
    let bundleIdentifier: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
        .onAppear { loadIcon() }
        .onChange(of: bundleIdentifier) { _, _ in loadIcon() }
    }

    private func loadIcon() {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            image = nil
            return
        }
        image = NSWorkspace.shared.icon(forFile: url.path)
    }
}
