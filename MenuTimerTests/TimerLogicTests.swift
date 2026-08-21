import XCTest
@testable import MenuTimer

final class TimerLogicTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testRunningTimerHasThirtyMinutesRemainingAfterThirtyMinutes() {
        let timer = makeTimer(duration: 3_600)
        let thirtyMinutesLater = start.addingTimeInterval(1_800)

        XCTAssertEqual(TimerLogic.remaining(for: timer, at: thirtyMinutesLater), 1_800, accuracy: 0.001)
    }

    func testPauseDoesNotContinueCountingWhileTheAppIsAway() {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)

        XCTAssertTrue(TimerLogic.pause(&timer, at: pausedAt))
        XCTAssertEqual(
            TimerLogic.remaining(for: timer, at: pausedAt.addingTimeInterval(1_200)),
            3_000,
            accuracy: 0.001
        )
    }

    func testResumeUsesCurrentTimePlusPausedRemainingDuration() {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        let resumedAt = pausedAt.addingTimeInterval(1_200)

        XCTAssertTrue(TimerLogic.pause(&timer, at: pausedAt))
        XCTAssertTrue(TimerLogic.resume(&timer, at: resumedAt))

        XCTAssertEqual(timer.targetEndDate, resumedAt.addingTimeInterval(3_000))
    }

    func testCompletedTimerIsClampedToZero() {
        var timer = makeTimer(duration: 60)
        XCTAssertTrue(TimerLogic.synchronize(&timer, at: start.addingTimeInterval(60)))
        XCTAssertEqual(timer.state, .completed)
        XCTAssertEqual(timer.remainingDuration, 0)
    }

    func testProgressIsIndependentForMultipleTimers() {
        let first = makeTimer(duration: 600)
        let second = makeTimer(duration: 7_200)
        let now = start.addingTimeInterval(300)

        XCTAssertEqual(TimerLogic.progress(for: first, at: now), 0.5, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.progress(for: second, at: now), 300.0 / 7_200.0, accuracy: 0.001)
    }

    func testPersistenceRoundTripPreservesTimerAndSelection() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerTests-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: temporaryDirectory.appendingPathComponent("timers.json"))
        let timer = makeTimer(duration: 3_600)
        let snapshot = TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id)

        try store.save(snapshot)
        let loaded = try store.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.selectedTimerID, timer.id)
        XCTAssertEqual(TimerLogic.remaining(for: loaded.timers[0], at: start.addingTimeInterval(1_800)), 1_800, accuracy: 0.001)

        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testMenuBarFormattingPrecision() {
        XCTAssertEqual(TimeFormatter.menuCountdown(2 * 86_400), "2d 00h")
        XCTAssertEqual(TimeFormatter.menuCountdown(2 * 3_600 + 14 * 60 + 37), "02:14")
        XCTAssertEqual(TimeFormatter.menuCountdown(58 * 60 + 37), "58:37")
        XCTAssertEqual(TimeFormatter.menuCountdown(9 * 60 + 42), "09:42")
        XCTAssertEqual(TimeFormatter.menuCountdown(-1), "00:00")

        let named = TimerItem(
            name: "面試",
            createdAt: start,
            kind: .duration,
            originalDuration: 2 * 3_600 + 14 * 60 + 37,
            targetEndDate: start.addingTimeInterval(2 * 3_600 + 14 * 60 + 37),
            remainingDuration: 2 * 3_600 + 14 * 60 + 37
        )
        XCTAssertEqual(
            TimeFormatter.menuBarTitle(for: named, at: start, format: .nameAndTime),
            "面試 02:14"
        )

        var completed = makeTimer(duration: 60)
        completed.state = .completed
        XCTAssertEqual(
            TimeFormatter.menuBarTitle(for: completed, at: start, format: .timeOnly),
            "✓ 完成"
        )
    }

    func testDeleteSelectedTimerChoosesAnotherOrNil() {
        let first = makeTimer(duration: 600)
        let second = makeTimer(duration: 1_200)
        let afterFirstDelete = TimerCollectionLogic.deletingTimer(
            id: first.id,
            from: [first, second],
            selectedTimerID: first.id
        )

        XCTAssertEqual(afterFirstDelete.timers.count, 1)
        XCTAssertEqual(afterFirstDelete.selectedTimerID, second.id)

        let afterLastDelete = TimerCollectionLogic.deletingTimer(
            id: second.id,
            from: afterFirstDelete.timers,
            selectedTimerID: afterFirstDelete.selectedTimerID
        )
        XCTAssertTrue(afterLastDelete.timers.isEmpty)
        XCTAssertNil(afterLastDelete.selectedTimerID)
    }

    func testPausePersistenceFreezesRemainingDuration() throws {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        XCTAssertTrue(TimerLogic.pause(&timer, at: pausedAt))

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerPause-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: temporaryDirectory.appendingPathComponent("timers.json"))
        try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
        let loaded = try store.load().timers[0]

        XCTAssertEqual(loaded.state, .paused)
        XCTAssertEqual(
            TimerLogic.remaining(for: loaded, at: pausedAt.addingTimeInterval(1_200)),
            3_000,
            accuracy: 0.001
        )
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCompletedPersistenceKeepsCompletedState() throws {
        var timer = makeTimer(duration: 60)
        XCTAssertTrue(TimerLogic.synchronize(&timer, at: start.addingTimeInterval(60)))

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerCompleted-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: temporaryDirectory.appendingPathComponent("timers.json"))
        try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
        let loaded = try store.load().timers[0]

        XCTAssertEqual(loaded.state, .completed)
        XCTAssertEqual(loaded.remainingDuration, 0)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testLongTimerFormattingDoesNotOverflow() {
        let oneHundredHours = 100 * 3_600.0
        XCTAssertEqual(TimeFormatter.menuCountdown(oneHundredHours), "4d 04h")
        XCTAssertEqual(TimeFormatter.detailCountdown(oneHundredHours), "4d 04h 00m")
    }

    func testScheduledFutureStartHasZeroProgressAndWaitingPhase() {
        let scheduledStart = start.addingTimeInterval(3_600)
        let timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)

        XCTAssertEqual(TimerLogic.phase(for: timer, at: start), .scheduled)
        XCTAssertEqual(TimerLogic.timeUntilStart(for: timer, at: start), 3_600, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remaining(for: timer, at: start), 0, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.progress(for: timer, at: start), 0, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remainingProgress(for: timer, at: start), 1, accuracy: 0.001)
    }

    func testScheduledActiveProgressIsTwentyFivePercent() {
        let timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let now = start.addingTimeInterval(2 * 86_400)

        XCTAssertEqual(TimerLogic.phase(for: timer, at: now), .running)
        XCTAssertEqual(TimerLogic.progress(for: timer, at: now), 0.25, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remainingProgress(for: timer, at: now), 0.75, accuracy: 0.001)
    }

    func testScheduledCompletedProgressIsClamped() {
        var timer = makeScheduledTimer(startDate: start.addingTimeInterval(-8 * 86_400), duration: 7 * 86_400)
        let now = start

        XCTAssertTrue(TimerLogic.synchronize(&timer, at: now))
        XCTAssertEqual(TimerLogic.phase(for: timer, at: now), .completed)
        XCTAssertEqual(TimerLogic.progress(for: timer, at: now), 1, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remainingProgress(for: timer, at: now), 0, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remaining(for: timer, at: now), 0, accuracy: 0.001)
    }

    func testScheduledMidpointIsFiftyPercent() {
        let timer = makeScheduledTimer(startDate: start, duration: 7 * 86_400)
        let midpoint = start.addingTimeInterval(3.5 * 86_400)

        XCTAssertEqual(TimerLogic.progress(for: timer, at: midpoint), 0.5, accuracy: 0.001)
        XCTAssertEqual(TimerLogic.remainingProgress(for: timer, at: midpoint), 0.5, accuracy: 0.001)
        XCTAssertEqual(TimeFormatter.elapsedPercentageText(for: timer, at: midpoint), "50.00%")
        XCTAssertEqual(TimeFormatter.remainingPercentageText(for: timer, at: midpoint), "50.00%")
    }

    func testScheduledPauseResumePreservesProgress() {
        var timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let pauseAt = start.addingTimeInterval(2 * 86_400)
        let resumeAt = pauseAt.addingTimeInterval(3 * 86_400)

        XCTAssertTrue(TimerLogic.pause(&timer, at: pauseAt))
        XCTAssertEqual(TimerLogic.phase(for: timer, at: resumeAt), .paused)
        XCTAssertEqual(TimerLogic.progress(for: timer, at: resumeAt), 0.25, accuracy: 0.001)
        XCTAssertTrue(TimerLogic.resume(&timer, at: resumeAt))
        XCTAssertEqual(TimerLogic.progress(for: timer, at: resumeAt), 0.25, accuracy: 0.001)
        XCTAssertEqual(timer.targetEndDate, resumeAt.addingTimeInterval(6 * 86_400))
    }

    func testScheduledPersistencePreservesSchedule() throws {
        let scheduledStart = start.addingTimeInterval(3_600)
        let timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerScheduled-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: temporaryDirectory.appendingPathComponent("timers.json"))

        try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
        let loaded = try store.load().timers[0]

        XCTAssertEqual(loaded.startDate, timer.startDate)
        XCTAssertEqual(loaded.originalStartDate, timer.originalStartDate)
        XCTAssertEqual(loaded.originalDuration, timer.originalDuration)
        XCTAssertEqual(loaded.targetEndDate, timer.targetEndDate)
        XCTAssertEqual(TimerLogic.progress(for: loaded, at: start), 0, accuracy: 0.001)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testScheduledResetRestoresOriginalPastSchedule() {
        let scheduledStart = start.addingTimeInterval(-8 * 86_400)
        var timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)
        let resetAt = start

        TimerLogic.reset(&timer, at: resetAt)

        XCTAssertEqual(timer.startDate, scheduledStart)
        XCTAssertEqual(timer.targetEndDate, scheduledStart.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(timer.state, .completed)
        XCTAssertEqual(timer.remainingDuration, 0, accuracy: 0.001)
    }

    func testV1JSONMigrationDefaultsStartDateFromCreatedAt() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let legacyJSON = """
        {
          "timers": [{
            "id": "\(id.uuidString)",
            "name": "舊 Timer",
            "createdAt": "1970-01-12T13:46:40Z",
            "kind": "duration",
            "originalDuration": 3600,
            "targetEndDate": "1970-01-12T14:46:40Z",
            "remainingDuration": 3600,
            "state": "running",
            "completionNotificationSent": true,
            "isSelected": true
          }],
          "selectedTimerID": "\(id.uuidString)"
        }
        """
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerMigration-\(UUID().uuidString)", isDirectory: true)
        let url = temporaryDirectory.appendingPathComponent("timers.json")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try legacyJSON.data(using: .utf8)!.write(to: url)

        let loaded = try TimerStore(fileURL: url).load().timers[0]
        XCTAssertEqual(loaded.startDate, loaded.createdAt)
        XCTAssertNil(loaded.originalStartDate)
        XCTAssertTrue(loaded.completionNotificationAttempted)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeTimer(duration: TimeInterval) -> TimerItem {
        TimerItem(
            name: "測試",
            createdAt: start,
            kind: .duration,
            originalDuration: duration,
            targetEndDate: start.addingTimeInterval(duration),
            remainingDuration: duration
        )
    }

    private func makeScheduledTimer(startDate: Date, duration: TimeInterval) -> TimerItem {
        TimerItem(
            name: "排程測試",
            createdAt: start,
            kind: .scheduledDuration,
            originalDuration: duration,
            targetEndDate: startDate.addingTimeInterval(duration),
            remainingDuration: duration,
            startDate: startDate,
            originalStartDate: startDate
        )
    }
}
