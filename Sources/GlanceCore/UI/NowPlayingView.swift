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
            .padding(.vertical, controller.items.count == 1 ? CompactPopupLayout.gap : 0)
            .frame(height: CompactPopupLayout.span(3))
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
                metadata(first, spacing: 2)
                    .padding(.leading, CompactPopupLayout.gap)
                    .padding(.trailing, CompactPopupLayout.gap)
                    .frame(height: 30)
                    .offset(y: (CompactPopupLayout.cardRowHeight - 30) / 2 - CompactPopupLayout.gap)
                Color.clear.frame(height: CompactPopupLayout.gap)
                MediaSeekSlider(item: first, controller: controller, date: date)
                    .padding(.horizontal, CompactPopupLayout.moduleTextInset)
                HStack {
                    Text(timeText(first.duration.map { $0 * (first.progress(at: date) ?? 0) } ?? first.elapsed)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.primary.opacity(0.78))
                    Spacer()
                    Text(timeText(first.duration.flatMap { $0 > 0 ? $0 : nil })).font(.system(size: 10)).monospacedDigit().foregroundStyle(.primary.opacity(0.78))
                }.padding(.horizontal, CompactPopupLayout.moduleTextInset)
                    .frame(height: 26)
                    .overlay { controls(first) }
                    .offset(y: (26 - CompactPopupLayout.cardRowHeight) / 2 + CompactPopupLayout.gap + 2.3)
            } else {
                ForEach(controller.items) { item in
                    HStack(spacing: 8) { metadata(item, spacing: 2).padding(.leading, CompactPopupLayout.gap); controls(item) }
                        .frame(height: CompactPopupLayout.cardRowHeight)
                    if item.id != controller.items.last?.id {
                        PopupDivider().padding(.horizontal, CompactPopupLayout.gap)
                    }
                }
            }
        }
    }

    private func metadata(_ item: NowPlayingItem, spacing: CGFloat = 1) -> some View {
        Button { controller.openSource(item) } label: {
            VStack(alignment: .leading, spacing: spacing) {
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(item.artist.isEmpty ? item.source : "\(item.artist) · \(item.source)")
                    .font(.system(size: 10)).foregroundStyle(.primary.opacity(0.78)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help(item.source)
    }

    private func controls(_ item: NowPlayingItem) -> some View {
        let alignsToFooter = controller.items.count > 1
        return HStack(spacing: alignsToFooter ? CompactPopupLayout.gap : 6) {
            button(.previous, symbol: "backward.fill", label: .mediaPrevious, item: item, enabled: item.canPrevious, alignment: alignsToFooter ? .trailing : .center)
            button(item.isPlaying ? .pause : .play, symbol: item.isPlaying ? "pause.fill" : "play.fill", label: item.isPlaying ? .mediaPause : .mediaPlay, item: item, enabled: item.isPlaying ? item.canPause : item.canPlay == true)
            button(.next, symbol: "forward.fill", label: .mediaNext, item: item, enabled: item.canNext)
        }
        .frame(width: alignsToFooter ? CompactPopupLayout.span(3) : nil)
    }

    private func button(_ action: NowPlayingCommand, symbol: String, label: LocalizationKey, item: NowPlayingItem, enabled: Bool, alignment: Alignment = .center) -> some View {
        Button { controller.send(action, to: item) } label: { Image(systemName: symbol).font(.system(size: CompactPopupLayout.moduleIconSize, weight: .medium)).frame(width: CompactPopupLayout.unit, height: 26, alignment: alignment).offset(x: alignment == .trailing ? 3 : (action == .next && controller.items.count > 1 ? -CompactPopupLayout.gap / 2 - 2.1 : 0)) }
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
            MediaProgressSlider(value: $draft, onEditingChanged: { editing in
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
            .controlSize(.mini)
            .disabled(item.canSeek != true)
            .accessibilityLabel("\(localization.string(.mediaProgress)) · \(item.source)")
            .frame(height: 12)
        } else {
            Capsule().fill(.primary.opacity(0.35)).frame(height: 2).frame(height: 12).accessibilityHidden(true)
        }
    }
}
