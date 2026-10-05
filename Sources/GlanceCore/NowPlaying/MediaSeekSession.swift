import Foundation

/// A gesture belongs to its original session even when the visible rows reorder.
struct MediaSeekSession {
    private var original: NowPlayingItem?

    mutating func begin(_ item: NowPlayingItem) { original = item }
    mutating func cancel() { original = nil }

    func commit(fraction: Double, currentItems: [NowPlayingItem]) -> (item: NowPlayingItem, position: Double)? {
        guard let original,
              let current = currentItems.first(where: { $0.id == original.id }),
              current.sourceBundleIdentifier == original.sourceBundleIdentifier,
              current.sourceProcessIdentifier == original.sourceProcessIdentifier,
              current.title == original.title, current.duration == original.duration,
              let position = current.seekPosition(fraction: fraction) else { return nil }
        return (current, position)
    }
}
