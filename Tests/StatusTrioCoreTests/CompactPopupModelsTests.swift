import XCTest
@testable import StatusTrioCore

final class CompactPopupModelsTests: XCTestCase {
    func testQuotaUsesActualWindowAndDoesNotInventSecondary() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1791589513},"secondary":null}}"#.utf8)
        let usage = try CodexUsageSnapshot.decode(data)
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows.first?.remainingPercent, 91)
        XCTAssertEqual(usage.windows.first?.windowDurationMins, 10080)
        XCTAssertEqual(usage.windows.first?.resetsAt, 1791589513)
    }

    func testQuotaPrefersMultiBucketAndClampsPercentages() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":120,"windowDurationMins":300},"secondary":{"usedPercent":-4,"windowDurationMins":10080}}}}"#.utf8)
        let usage = try CodexUsageSnapshot.decode(data)
        XCTAssertEqual(usage.windows.map(\.remainingPercent), [0, 100])
        XCTAssertNil(usage.windows[0].resetsAt)
    }

    func testPlayingRowsRemovePausedAndDuplicateSources() {
        let a = media("a", playing: true)
        let b = media("b", playing: true)
        XCTAssertEqual(NowPlayingItem.visible([a, media("paused", playing: false), a, b]).map(\.id), ["a", "b"])
        XCTAssertTrue(NowPlayingItem.visible([media("paused", playing: false)]).isEmpty)
    }

    func testSystemPausedSessionRemainsVisibleWithFrozenProgress() throws {
        let data = Data(#"{"id":"paused","title":"Title","artist":"Artist","source":"App","isPlaying":false,"playbackState":2,"elapsed":5,"duration":30,"timestamp":100,"playbackRate":1,"canPause":false,"canPlay":true,"canNext":true,"canPrevious":true}"#.utf8)
        let paused = try JSONDecoder().decode(NowPlayingItem.self, from: data)
        XCTAssertEqual(NowPlayingItem.visible([paused]).map(\.id), ["paused"])
        XCTAssertEqual(paused.progress(at: Date(timeIntervalSince1970: 200)), 5.0 / 30)
        XCTAssertEqual(NowPlayingItem.visible([paused, media("playing", playing: true)]).map(\.id), ["playing", "paused"])
        XCTAssertTrue(NowPlayingItem.visible([]).isEmpty)
    }

    func testProgressClampsAndIgnoresUnknownDuration() {
        let a = media("a", playing: true)
        XCTAssertEqual(a.progress(at: Date(timeIntervalSince1970: 150)), 1)
        var live = a
        live.duration = nil
        XCTAssertNil(live.progress(at: Date()))
    }

    @MainActor
    func testQuotaRefreshesOnEveryReopenEvenImmediatelyAfterLastAttempt() {
        var attempts = 0
        let controller = CodexUsageController(executable: { attempts += 1; return nil })
        controller.setVisible(true)
        XCTAssertEqual(attempts, 1)
        controller.setVisible(false)
        controller.setVisible(true)
        XCTAssertEqual(attempts, 2)
        controller.setVisible(false)
    }

    @MainActor
    func testManualQuotaRefreshOnlyRunsWhilePanelIsVisible() {
        var attempts = 0
        let controller = CodexUsageController(executable: { attempts += 1; return nil })
        controller.refreshNow()
        XCTAssertEqual(attempts, 0)
        controller.setVisible(true)
        controller.refreshNow()
        XCTAssertEqual(attempts, 2)
        controller.setVisible(false)
        controller.refreshNow()
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testPopupClearsMenuBarWhenStatusButtonAnchorIsHigher() {
        let frame = StatusPopupPanel.frame(for: NSSize(width: 284, height: 220),
            anchor: NSRect(x: 1400, y: 888, width: 24, height: 12),
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 875), menuBarBottom: 875)
        XCTAssertEqual(frame.maxY, 875)
        XCTAssertLessThanOrEqual(frame.maxX, 1512)
    }

    @MainActor
    func testPopupAlignsWithAnchorWhenItIsBelowMenuBarOnAnotherScreen() {
        let frame = StatusPopupPanel.frame(for: NSSize(width: 284, height: 220),
            anchor: NSRect(x: -1600, y: 770, width: 24, height: 24),
            screenFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1000), menuBarBottom: 800)
        XCTAssertEqual(frame.maxY, 770)
        XCTAssertGreaterThanOrEqual(frame.minX, -1920)
    }

    func testSeekingRequiresCapabilityAndClampsPosition() {
        var item = media("a", playing: true)
        XCTAssertNil(item.seekPosition(fraction: 0.5))
        item.canSeek = true
        XCTAssertEqual(item.seekPosition(fraction: 0.5), 15)
        XCTAssertEqual(item.seekPosition(fraction: -1), 0)
        XCTAssertEqual(item.seekPosition(fraction: 2), 30)
        XCTAssertNil(item.seekPosition(fraction: .nan))
        item.duration = nil
        XCTAssertNil(item.seekPosition(fraction: 0.5))
    }

    func testSeekGestureKeepsOriginalSourceWhenRowsReorder() {
        var chrome = media("chrome", playing: true)
        chrome.canSeek = true
        var music = media("music", playing: true)
        music.canSeek = true
        var session = MediaSeekSession()
        session.begin(chrome)
        let commit = session.commit(fraction: 0.5, currentItems: [music, chrome])
        XCTAssertEqual(commit?.item.id, "chrome")
        XCTAssertEqual(commit?.position, 15)
        XCTAssertNil(session.commit(fraction: 0.5, currentItems: [music]))
        session.cancel()
        XCTAssertNil(session.commit(fraction: 0.5, currentItems: [chrome]))
    }

    private func media(_ id: String, playing: Bool) -> NowPlayingItem {
        NowPlayingItem(id: id, title: "Title", artist: "Artist", source: "App", isPlaying: playing,
                       elapsed: 5, duration: 30, timestamp: 100, playbackRate: playing ? 1 : 0,
                       canPause: true, canNext: true, canPrevious: true)
    }
}
