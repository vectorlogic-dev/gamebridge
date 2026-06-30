import XCTest
@testable import GameBridge

@MainActor
final class HoldRunnerTests: XCTestCase {
    func testArmOnCurrentAppCapturesFrontmostAppAndSendsInitialKeyDown() async throws {
        var events: [RecordedKeyEvent] = []
        let repeatStarted = expectation(description: "repeat loop started")
        let released = expectation(description: "released")

        let runner = HoldRunner(
            frontmostAppProvider: { FrontmostApp(pid: 4242, name: "RF Online") },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
                if events.count == 2 { repeatStarted.fulfill() }
            },
            keyUpHandler: { key, pid in
                events.append(.up(key: key, pid: pid))
                released.fulfill()
            },
            sleepHandler: { _ in
                await Task.yield()
            }
        )

        runner.armOnCurrentApp()
        await fulfillment(of: [repeatStarted], timeout: 1.0)
        runner.disarm()
        await fulfillment(of: [released], timeout: 1.0)

        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(events.first, .down(key: .n1, pid: 4242, autorepeat: false))
        XCTAssertTrue(events.contains(.down(key: .n1, pid: 4242, autorepeat: true)))
        XCTAssertEqual(events.filter(\.isKeyUp).count, 1)
        XCTAssertEqual(events.last, .up(key: .n1, pid: 4242))
    }

    func testArmOnCurrentAppDoesNothingWhenAlreadyHolding() async {
        var frontmostAppCalls = 0
        var events: [RecordedKeyEvent] = []
        let sleepStarted = expectation(description: "sleep started")
        let sleepGate = SleepGate()

        let runner = HoldRunner(
            frontmostAppProvider: {
                frontmostAppCalls += 1
                return FrontmostApp(pid: 4242, name: "RF Online")
            },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
            },
            keyUpHandler: { _, _ in },
            sleepHandler: { _ in
                sleepStarted.fulfill()
                await sleepGate.wait()
            }
        )

        runner.armOnCurrentApp()
        await fulfillment(of: [sleepStarted], timeout: 1.0)
        runner.armOnCurrentApp()
        runner.disarm()
        await sleepGate.resume()
        await Task.yield()

        XCTAssertEqual(frontmostAppCalls, 1)
        XCTAssertEqual(
            events.filter { $0 == .down(key: .n1, pid: 4242, autorepeat: false) }.count,
            1
        )
        XCTAssertEqual(events.filter(\.isAutorepeatKeyDown).count, 0)
    }

    func testDisarmIsSafeWhileIdle() {
        let runner = HoldRunner(
            frontmostAppProvider: { nil },
            keyDownHandler: { _, _, _ in XCTFail("Unexpected keyDown") },
            keyUpHandler: { _, _ in XCTFail("Unexpected keyUp") },
            sleepHandler: { _ in await Task.yield() }
        )

        runner.disarm()

        XCTAssertEqual(runner.state, .idle)
    }

    func testDisarmEmitsSingleImmediateKeyUpAndStopsFurtherRepeats() async throws {
        var events: [RecordedKeyEvent] = []
        let sleepStarted = expectation(description: "sleep started")
        let sleepGate = SleepGate()

        let runner = HoldRunner(
            frontmostAppProvider: { FrontmostApp(pid: 4242, name: "RF Online") },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
            },
            keyUpHandler: { key, pid in
                events.append(.up(key: key, pid: pid))
            },
            sleepHandler: { _ in
                sleepStarted.fulfill()
                await sleepGate.wait()
            }
        )

        runner.armOnCurrentApp()
        await fulfillment(of: [sleepStarted], timeout: 1.0)

        runner.disarm()

        XCTAssertEqual(events.filter(\.isKeyUp).count, 1)
        XCTAssertEqual(events.last, .up(key: .n1, pid: 4242))
        XCTAssertEqual(events.filter(\.isAutorepeatKeyDown).count, 0)

        await sleepGate.resume()
        await Task.yield()

        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(events.filter(\.isKeyUp).count, 1)
        XCTAssertEqual(events.filter(\.isAutorepeatKeyDown).count, 0)
        XCTAssertEqual(events.last, .up(key: .n1, pid: 4242))
    }

    func testImmediateDisarmThenRearmDoesNotReleaseIntoNewHold() async throws {
        var events: [RecordedKeyEvent] = []
        var frontmostApps = [
            FrontmostApp(pid: 1111, name: "RF Online"),
            FrontmostApp(pid: 2222, name: "RF Online")
        ]
        let firstSleepStarted = expectation(description: "first sleep started")
        let secondSleepStarted = expectation(description: "second sleep started")
        let firstGate = SleepGate()
        let secondGate = SleepGate()
        var sleepCalls = 0

        let runner = HoldRunner(
            frontmostAppProvider: {
                guard !frontmostApps.isEmpty else { return nil }
                return frontmostApps.removeFirst()
            },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
            },
            keyUpHandler: { key, pid in
                events.append(.up(key: key, pid: pid))
            },
            sleepHandler: { _ in
                sleepCalls += 1
                if sleepCalls == 1 {
                    firstSleepStarted.fulfill()
                    await firstGate.wait()
                } else {
                    secondSleepStarted.fulfill()
                    await secondGate.wait()
                }
            }
        )

        runner.armOnCurrentApp()
        await fulfillment(of: [firstSleepStarted], timeout: 1.0)

        runner.disarm()
        XCTAssertEqual(events.last, .up(key: .n1, pid: 1111))
        XCTAssertEqual(events.filter { $0 == .up(key: .n1, pid: 1111) }.count, 1)

        runner.armOnCurrentApp()
        await fulfillment(of: [secondSleepStarted], timeout: 1.0)

        XCTAssertEqual(events.suffix(2), [
            .up(key: .n1, pid: 1111),
            .down(key: .n1, pid: 2222, autorepeat: false)
        ])

        await firstGate.resume()
        await Task.yield()

        XCTAssertEqual(events.filter { $0 == .up(key: .n1, pid: 1111) }.count, 1)
        XCTAssertFalse(events.dropLast().contains(.up(key: .n1, pid: 2222)))

        runner.disarm()
        XCTAssertEqual(events.filter { $0 == .up(key: .n1, pid: 2222) }.count, 1)

        await secondGate.resume()
        await Task.yield()

        XCTAssertEqual(events.filter { $0 == .up(key: .n1, pid: 1111) }.count, 1)
        XCTAssertEqual(events.filter { $0 == .up(key: .n1, pid: 2222) }.count, 1)
    }

    func testDisarmReleasesOriginallyArmedKeyWhenTargetKeyChangesMidHold() async throws {
        var events: [RecordedKeyEvent] = []
        let sleepStarted = expectation(description: "sleep started")
        let sleepGate = SleepGate()

        let runner = HoldRunner(
            frontmostAppProvider: { FrontmostApp(pid: 4242, name: "RF Online") },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
            },
            keyUpHandler: { key, pid in
                events.append(.up(key: key, pid: pid))
            },
            sleepHandler: { _ in
                sleepStarted.fulfill()
                await sleepGate.wait()
            }
        )

        runner.targetKey = .n2
        runner.armOnCurrentApp()
        await fulfillment(of: [sleepStarted], timeout: 1.0)

        runner.targetKey = .n7
        runner.disarm()

        XCTAssertEqual(events.first, .down(key: .n2, pid: 4242, autorepeat: false))
        XCTAssertEqual(events.last, .up(key: .n2, pid: 4242))

        await sleepGate.resume()
        await Task.yield()
    }
}

private enum RecordedKeyEvent: Equatable {
    case down(key: NumberKey, pid: pid_t, autorepeat: Bool)
    case up(key: NumberKey, pid: pid_t)

    var isKeyUp: Bool {
        if case .up = self {
            return true
        }
        return false
    }

    var isAutorepeatKeyDown: Bool {
        if case let .down(_, _, autorepeat) = self {
            return autorepeat
        }
        return false
    }
}

private actor SleepGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
