import XCTest
@testable import GlanceCore

final class PerformanceTests: XCTestCase {
    func testCPUUsesIntervalRatherThanLifetimeAndHandlesCounterWrap() {
        XCTAssertEqual(PerformanceSampler.cpuPercent(previous: [100, 200, 300, 400], current: [110, 220, 360, 410]), 40)
        XCTAssertNil(PerformanceSampler.cpuPercent(previous: [1, 2, 3, 4], current: [1, 2, 3, 4]))
        XCTAssertNil(PerformanceSampler.cpuPercent(previous: [], current: []))
        XCTAssertEqual(PerformanceSampler.cpuPercent(previous: [UInt32.max - 4, 0, 0, 0], current: [5, 0, 10, 0]), 50)
    }

    func testMemoryExcludesCacheAndBoundsInconsistentCounters() {
        XCTAssertEqual(PerformanceSampler.usedMemory(residentPages: 100, cachedPages: 20, pageSize: 4096, total: 1_000_000), 327680)
        XCTAssertEqual(PerformanceSampler.usedMemory(residentPages: 10, cachedPages: 20, pageSize: 4096, total: 1_000_000), 0)
        XCTAssertEqual(PerformanceSampler.usedMemory(residentPages: 100, cachedPages: 0, pageSize: 4096, total: 100), 100)
        XCTAssertEqual(PerformanceSampler.usedMemory(residentPages: UInt64.max, cachedPages: 0, pageSize: 4096, total: 100), 100)
    }

    @MainActor
    func testLiveSamplingStartsWithVisibilityAndStopsWhenHidden() async throws {
        let controller = PerformanceController()
        XCTAssertNil(controller.snapshot)
        controller.setVisible(true)
        let first = try XCTUnwrap(controller.snapshot)
        XCTAssertGreaterThan(first.totalMemory, 0)
        XCTAssertLessThanOrEqual(first.usedMemory, first.totalMemory)
        XCTAssertNil(first.cpuPercent, "CPU requires a fresh interval, not lifetime counters")
        for _ in 0..<150 {
            if controller.snapshot?.cpuPercent != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let sampled = try XCTUnwrap(controller.snapshot?.cpuPercent)
        XCTAssertTrue((0...100).contains(sampled))
        controller.setVisible(false)
        let frozen = controller.snapshot
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(controller.snapshot, frozen)
    }
}
