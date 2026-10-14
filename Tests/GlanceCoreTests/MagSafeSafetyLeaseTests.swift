import XCTest
@testable import MagSafeSMC

final class MagSafeSafetyLeaseTests: XCTestCase {
    func testShutdownRejectsQueuedOffCommandsAndRenewals() {
        let hardware = LeaseHardware()
        let lease = MagSafeSafetyLease(now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertTrue(lease.set(.off))
        XCTAssertTrue(lease.shutdown())
        XCTAssertFalse(lease.set(.off))
        XCTAssertFalse(lease.renew())
        XCTAssertEqual(hardware.commands, [.off, .system])
    }

    func testLostClientRestoresSystemAfterLeaseExpires() {
        let hardware = LeaseHardware()
        let lease = MagSafeSafetyLease(duration: 30, now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertTrue(lease.set(.off))
        hardware.time = 29
        lease.expireIfNeeded()
        XCTAssertEqual(hardware.commands, [.off])
        hardware.time = 30
        lease.expireIfNeeded()
        XCTAssertEqual(hardware.commands, [.off, .system])
        XCTAssertFalse(lease.needsRestoration)
    }

    func testRenewalExtendsDeadlineWithoutRewritingHardware() {
        let hardware = LeaseHardware()
        let lease = MagSafeSafetyLease(duration: 30, now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertTrue(lease.set(.off))
        hardware.time = 20
        XCTAssertTrue(lease.renew())
        hardware.time = 31
        lease.expireIfNeeded()
        XCTAssertTrue(lease.needsRestoration)
        XCTAssertEqual(hardware.commands, [.off])
        hardware.time = 50
        lease.expireIfNeeded()
        XCTAssertEqual(hardware.commands, [.off, .system])
    }

    func testFailedOffAcknowledgementStillRequiresRestoration() {
        let hardware = LeaseHardware()
        hardware.succeeds = false
        let lease = MagSafeSafetyLease(duration: 30, now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertFalse(lease.set(.off))
        XCTAssertTrue(lease.needsRestoration)
        hardware.time = 31
        lease.expireIfNeeded()
        XCTAssertTrue(lease.needsRestoration)
        hardware.succeeds = true
        lease.expireIfNeeded()
        XCTAssertFalse(lease.needsRestoration)
        XCTAssertEqual(hardware.commands, [.off, .system, .system])
    }

    func testExpiredLeaseCannotBeRevivedWithoutAnExplicitOffCommand() {
        let hardware = LeaseHardware()
        let lease = MagSafeSafetyLease(duration: 30, now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertFalse(lease.renew())
        XCTAssertTrue(lease.set(.off))
        hardware.time = 31
        XCTAssertFalse(lease.renew())
        lease.expireIfNeeded()
        XCTAssertFalse(lease.renew())
    }

    func testSystemModeClearsLeaseAndShutdownRestoresOutstandingState() {
        let hardware = LeaseHardware()
        let lease = MagSafeSafetyLease(duration: 30, now: { hardware.time }, apply: { hardware.write($0) })
        XCTAssertTrue(lease.set(.off))
        XCTAssertTrue(lease.restore())
        XCTAssertFalse(lease.needsRestoration)
        XCTAssertTrue(lease.restore())
        XCTAssertEqual(hardware.commands, [.off, .system])
    }
}

private final class LeaseHardware: @unchecked Sendable {
    // Tests drive the lease synchronously on one thread.
    var time: TimeInterval = 0
    var succeeds = true
    var commands: [MagSafeLEDCommand] = []
    func write(_ mode: MagSafeLEDCommand) -> Bool { commands.append(mode); return succeeds }
}
