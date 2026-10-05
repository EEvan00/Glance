import XCTest
import Darwin
@testable import StatusTrioCore

@MainActor
final class JSONLineProcessTests: XCTestCase {
    func testReadsSplitLinesWithoutPublishingPartialJSON() async throws {
        let runner = JSONLineProcess()
        var lines: [String] = []
        try runner.start(executable: URL(fileURLWithPath: "/bin/sh"),
                         arguments: ["-c", "printf '{\"ok\":'; sleep 0.05; printf 'true}\\n'; sleep 0.1"],
                         timeout: 2, onLine: { lines.append(String(decoding: $0, as: UTF8.self)) }, onExit: { _ in })
        for _ in 0..<100 {
            if !lines.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(lines, ["{\"ok\":true}"])
        runner.stop()
    }

    func testStopTerminatesChildAndRejectsLateOutput() async throws {
        let runner = JSONLineProcess()
        var lines: [String] = []
        try runner.start(executable: URL(fileURLWithPath: "/bin/sh"),
                         arguments: ["-c", "echo $$; exec /bin/sleep 30"],
                         onLine: { lines.append(String(decoding: $0, as: UTF8.self)) }, onExit: { _ in })
        for _ in 0..<100 {
            if !lines.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try XCTUnwrap(lines.first.flatMap(Int32.init))
        runner.stop()
        for _ in 0..<100 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(runner.isRunning)
        XCTAssertNotEqual(kill(pid, 0), 0, "Dismissal must stop the real child")
        XCTAssertEqual(lines.count, 1)
    }

    func testFinalLinesArriveBeforeExitAndEOFDoesNotSpin() async throws {
        let runner = JSONLineProcess()
        var events: [String] = []
        try runner.start(executable: URL(fileURLWithPath: "/bin/sh"),
                         arguments: ["-c", "printf 'first\\nlast\\n'; exec 1>&-; sleep 0.1"], timeout: 2,
                         onLine: { events.append(String(decoding: $0, as: UTF8.self)) },
                         onExit: { _ in events.append("exit") })
        for _ in 0..<100 {
            if events.last == "exit" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(events, ["first", "last", "exit"])
        XCTAssertFalse(runner.isRunning)
    }

    func testTimeoutStopsUnresponsiveChild() async throws {
        let runner = JSONLineProcess()
        var exitStatus: Int32?
        try runner.start(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.05,
                         onLine: { _ in XCTFail("Unexpected output") }, onExit: { exitStatus = $0 })
        for _ in 0..<100 {
            if exitStatus != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(exitStatus, -1)
        XCTAssertFalse(runner.isRunning)
    }
}
