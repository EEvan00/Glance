import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var controller: NowPlayingController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        if !controller.items.isEmpty {
            Group {
                if controller.items.count == 1 && controller.items.contains(where: { $0.isPlaying }) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        rows(at: context.date)
                    }
                } else {
                    rows(at: .now)
                }
            }
            .padding(.horizontal, CompactPopupLayout.contentInset)
            .padding(.vertical, CompactPopupLayout.gap)
            .systemModuleSurface()
            .overlay(alignment: .bottom) {
                if controller.commandFailed {
                    Text(localization.string(.mediaCommandFailed)).font(.system(size: 9)).foregroundStyle(.primary.opacity(0.78))
                }
            }
        }
    }

    private func rows(at date: Date) -> some View {
        VStack(spacing: 0) {
            if let first = controller.items.first, controller.items.count == 1 {
                metadata(first).frame(height: 40)
                Color.clear.frame(height: CompactPopupLayout.gap)
                VStack(spacing: 2) {
                    MediaSeekSlider(item: first, controller: controller, date: date)
                    HStack {
                        Text(timeText(first.duration.map { $0 * (first.progress(at: date) ?? 0) } ?? first.elapsed)).font(.system(size: 9)).monospacedDigit().foregroundStyle(.primary.opacity(0.78))
                        Spacer()
                        controls(first)
                        Spacer()
                        Text(timeText(first.duration.flatMap { $0 > 0 ? $0 : nil })).font(.system(size: 9)).monospacedDigit().foregroundStyle(.primary.opacity(0.78))
                    }
                }.frame(height: 40)
            } else {
                ForEach(controller.items) { item in
                    HStack(spacing: 8) { metadata(item); controls(item) }.frame(height: 40)
                    if item.id != controller.items.last?.id {
                        PopupDivider().frame(height: CompactPopupLayout.gap)
                    }
                }
            }
        }
    }

    private func metadata(_ item: NowPlayingItem) -> some View {
        Button { controller.openSource(item) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(item.artist.isEmpty ? item.source : "\(item.artist) · \(item.source)")
                    .font(.system(size: 10)).foregroundStyle(.primary.opacity(0.78)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help(item.source)
    }

    private func controls(_ item: NowPlayingItem) -> some View {
        HStack(spacing: 6) {
            button(.previous, symbol: "backward.fill", label: .mediaPrevious, item: item, enabled: item.canPrevious)
            button(item.isPlaying ? .pause : .play, symbol: item.isPlaying ? "pause.fill" : "play.fill", label: item.isPlaying ? .mediaPause : .mediaPlay, item: item, enabled: item.isPlaying ? item.canPause : item.canPlay == true)
            button(.next, symbol: "forward.fill", label: .mediaNext, item: item, enabled: item.canNext)
        }
    }

    private func button(_ action: NowPlayingCommand, symbol: String, label: LocalizationKey, item: NowPlayingItem, enabled: Bool) -> some View {
        Button { controller.send(action, to: item) } label: { Image(systemName: symbol).font(.system(size: 15)).frame(width: 26, height: 26) }
            .buttonStyle(.plain).disabled(!enabled)
            .accessibilityLabel("\(localization.string(label)) · \(item.source)")
            .help(localization.string(label))
    }

    private func timeText(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let value = Int(min(seconds, 359_999))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct MediaSeekSlider: View {
    let item: NowPlayingItem
    @ObservedObject var controller: NowPlayingController
    let date: Date
    @State private var draft = 0.0
    @State private var isEditing = false
    @State private var seekSession = MediaSeekSession()
    @EnvironmentObject private var localization: Localization

    var body: some View {
        if item.progress(at: .now) != nil {
            Slider(value: $draft, in: 0...1, onEditingChanged: { editing in
                isEditing = editing
                if editing {
                    seekSession.begin(item)
                } else {
                    if let commit = seekSession.commit(fraction: draft, currentItems: controller.items) {
                        controller.send(.seek, to: commit.item, position: commit.position)
                    }
                    seekSession.cancel()
                }
            })
            .onAppear { draft = item.progress(at: date) ?? 0 }
            .onChange(of: date) { _, date in if !isEditing { draft = item.progress(at: date) ?? 0 } }
            .onChange(of: item) { previous, item in
                if previous.id != item.id || previous.title != item.title || previous.duration != item.duration {
                    seekSession.cancel()
                    isEditing = false
                }
                if !isEditing { draft = item.progress(at: date) ?? 0 }
            }
            .onDisappear { seekSession.cancel(); isEditing = false }
            .controlSize(.mini).tint(Color(white: 0.72))
            .disabled(item.canSeek != true)
            .accessibilityLabel("\(localization.string(.mediaProgress)) · \(item.source)")
            .frame(height: 12)
        } else {
            Capsule().fill(.primary.opacity(0.35)).frame(height: 2).frame(height: 12).accessibilityHidden(true)
        }
    }
}
