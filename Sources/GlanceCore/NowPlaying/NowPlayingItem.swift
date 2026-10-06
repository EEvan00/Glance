import Foundation

struct NowPlayingItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let source: String
    let isPlaying: Bool
    let elapsed: Double
    var duration: Double?
    let timestamp: TimeInterval
    let playbackRate: Double
    let canPause: Bool
    let canNext: Bool
    let canPrevious: Bool
    var canSeek: Bool? = nil
    var canPlay: Bool? = nil
    var playbackState: Int? = nil
    var sourceBundleIdentifier: String? = nil
    var sourceProcessIdentifier: Int32? = nil
    var artworkData: Data? = nil

    static func visible(_ items: [Self]) -> [Self] {
        var seen = Set<String>()
        return Array(items.filter {
            ($0.isPlaying || $0.playbackState == 2) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert($0.id).inserted
        }.enumerated().sorted {
            if $0.element.isPlaying != $1.element.isPlaying { return $0.element.isPlaying }
            return $0.offset < $1.offset
        }.prefix(2).map(\.element))
    }

    func seekPosition(fraction: Double) -> Double? {
        guard canSeek == true, fraction.isFinite, let duration, duration.isFinite, duration > 0 else { return nil }
        return min(1, max(0, fraction)) * duration
    }

    func progress(at date: Date) -> Double? {
        guard let duration, duration.isFinite, duration > 0,
              elapsed.isFinite, timestamp.isFinite, playbackRate.isFinite else { return nil }
        let projected = elapsed + (isPlaying ? max(0, date.timeIntervalSince1970 - timestamp) * playbackRate : 0)
        return min(1, max(0, projected / duration))
    }
}

enum NowPlayingCommand: Int, Sendable {
    case play = 0
    case seek = 24
    case pause = 1
    case next = 4
    case previous = 5
}
