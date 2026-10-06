import Combine
import Foundation

@MainActor
final class CountdownController: ObservableObject {
    static let completionFlashDuration: TimeInterval = 5
    @Published private(set) var deadline: Date?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isFinished = false
    @Published private(set) var finishedAt: Date?
    @Published var notificationsUnavailable = false
    @Published var shouldOpenDetails = false
    private(set) var duration: TimeInterval = 0
    var onSchedule: ((Date?) -> Void)?
    var onFinish: (() -> Void)?
    var indicator: CountdownIndicator? {
        guard isRunning || isPaused || isFinished else { return nil }
        let elapsed = finishedAt.map { max(0, now().timeIntervalSince($0)) } ?? Self.completionFlashDuration
        return CountdownIndicator(remaining: remaining, duration: duration,
                                  isDimmed: isFinished && elapsed < Self.completionFlashDuration && Int(elapsed / 0.25) % 2 == 0)
    }
    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { deadline == nil && remaining > 0 }
    private let defaults: UserDefaults
    private let now: () -> Date
    private var ticker: AnyCancellable?
    private var blinkTicker: AnyCancellable?
    private let automaticTicks: Bool
    private static let key = "countdownState"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }, automaticTicks: Bool = true) {
        self.automaticTicks = automaticTicks
        self.defaults = defaults
        self.now = now
        if let saved = defaults.dictionary(forKey: Self.key),
           let duration = saved["duration"] as? Double, duration > 0 {
            self.duration = duration
            if let timestamp = saved["deadline"] as? Double {
                deadline = Date(timeIntervalSince1970: timestamp)
                remaining = max(0, deadline!.timeIntervalSince(now()))
            } else {
                remaining = max(0, saved["remaining"] as? Double ?? 0)
                isFinished = saved["finished"] as? Bool ?? false
            }
        }
        if isFinished { clearState() }
        if isRunning { startTicker() }
    }

    private func startTicker() {
        guard automaticTicks else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func start(minutes: Int) {
        guard (1...1440).contains(minutes) else { return }
        blinkTicker = nil
        duration = Double(minutes * 60)
        remaining = duration
        isFinished = false
        finishedAt = nil
        deadline = now().addingTimeInterval(duration)
        startTicker()
        persist()
        onSchedule?(deadline)
    }

    func pause() {
        guard isRunning else { return }
        tick()
        guard isRunning else { return }
        deadline = nil
        ticker = nil
        persist()
        onSchedule?(nil)
    }

    func resume() {
        guard isPaused else { return }
        deadline = now().addingTimeInterval(remaining)
        startTicker()
        persist()
        onSchedule?(deadline)
    }

    func cancel() {
        clearState()
        onSchedule?(nil)
    }

    private func clearState() {
        ticker = nil
        blinkTicker = nil
        deadline = nil
        remaining = 0
        duration = 0
        isFinished = false
        finishedAt = nil
        defaults.removeObject(forKey: Self.key)
    }

    func tick() {
        guard let deadline else {
            if let finishedAt {
                if now().timeIntervalSince(finishedAt) >= Self.completionFlashDuration {
                    // Keep the delivered notification while clearing all timer work and its icon override.
                    clearState()
                }
                else { objectWillChange.send() }
            }
            return
        }
        remaining = max(0, deadline.timeIntervalSince(now()))
        if remaining == 0 {
            self.deadline = nil
            ticker = nil
            isFinished = true
            finishedAt = now()
            if automaticTicks {
                blinkTicker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.tick() }
                }
            }
            persist()
            onFinish?()
        }
    }

    static func display(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func persist() {
        var saved: [String: Any] = ["duration": duration, "remaining": remaining, "finished": isFinished]
        if let deadline { saved["deadline"] = deadline.timeIntervalSince1970 }
        defaults.set(saved, forKey: Self.key)
    }
}
