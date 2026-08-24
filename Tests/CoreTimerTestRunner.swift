import Foundation
@testable import MenuTimerCore

@main
struct CoreTimerTestRunner {
    private static let start = Date(timeIntervalSince1970: 1_000_000)

    static func main() {
        testRunningTimerUsesTargetDateForRemainingTime()
        testPauseFreezesRemainingDuration()
        testResumeBuildsNewTargetFromPausedDuration()
        testTimerCompletesAtZeroAndNeverGoesNegative()
        testResetRestoresOriginalDurationForEndDateTimer()
        testMultipleTimersDoNotInterfere()
        testPersistenceRoundTripPreservesTimerAndSelection()
        testMenuBarFormattingPrecision()
        testDeleteSelectedTimerChoosesAnotherOrNil()
        testPausePersistenceFreezesRemainingDuration()
        testCompletedPersistenceKeepsCompletedState()
        testLongTimerFormattingDoesNotOverflow()
        testTimerStoreHandlesMissingAndCorruptJSON()
        testScheduledFutureStartHasZeroProgressAndWaitingPhase()
        testScheduledActiveProgressIsTwentyFivePercent()
        testScheduledCompletedProgressIsClamped()
        testScheduledMidpointIsFiftyPercent()
        testScheduledPauseResumePreservesProgress()
        testScheduledPersistencePreservesSchedule()
        testScheduledResetRestoresOriginalPastSchedule()
        testRescheduleRunningScheduledTimerReplacesSchedule()
        testRescheduleActiveScheduledTimerUsesNewProgress()
        testReschedulePausedTimerClearsPausedSnapshot()
        testRescheduleCompletedTimerCreatesNewSchedule()
        testReschedulePastScheduleCompletesImmediately()
        testRescheduledSchedulePersistenceRoundTrip()
        testV1JSONMigrationDefaultsStartDateFromCreatedAt()
        print("MenuTimerCoreTestRunner: 27 tests passed")
    }

    private static func testRunningTimerUsesTargetDateForRemainingTime() {
        let timer = makeTimer(duration: 3_600)
        let later = start.addingTimeInterval(1_800)
        expect(
            abs(TimerLogic.remaining(for: timer, at: later) - 1_800) < 0.001,
            "running timer should use target date"
        )
    }

    private static func testPauseFreezesRemainingDuration() {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        expect(TimerLogic.pause(&timer, at: pausedAt), "pause should transition running timer")
        let later = pausedAt.addingTimeInterval(1_200)
        expect(
            abs(TimerLogic.remaining(for: timer, at: later) - 3_000) < 0.001,
            "paused timer should not continue counting"
        )
    }

    private static func testResumeBuildsNewTargetFromPausedDuration() {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        let resumedAt = pausedAt.addingTimeInterval(1_200)
        expect(TimerLogic.pause(&timer, at: pausedAt), "pause should succeed")
        expect(TimerLogic.resume(&timer, at: resumedAt), "resume should succeed")
        expect(
            timer.targetEndDate == resumedAt.addingTimeInterval(3_000),
            "resume should rebuild target from paused duration"
        )
    }

    private static func testTimerCompletesAtZeroAndNeverGoesNegative() {
        var timer = makeTimer(duration: 60)
        let completion = start.addingTimeInterval(60)
        expect(TimerLogic.synchronize(&timer, at: completion), "timer should transition to completed")
        expect(timer.state == .completed, "completed timer should have completed state")
        expect(timer.remainingDuration == 0, "completed timer should be clamped to zero")
        expect(
            TimerLogic.remaining(for: timer, at: completion.addingTimeInterval(60)) == 0,
            "completed timer should never become negative"
        )
    }

    private static func testResetRestoresOriginalDurationForEndDateTimer() {
        var timer = TimerItem(
            name: "指定時間",
            createdAt: start,
            kind: .endDate,
            originalDuration: 900,
            targetEndDate: start.addingTimeInterval(900),
            remainingDuration: 0,
            state: .completed
        )
        let resetAt = start.addingTimeInterval(3_600)
        TimerLogic.reset(&timer, at: resetAt)
        expect(timer.state == .running, "reset should restart timer")
        expect(timer.targetEndDate == resetAt.addingTimeInterval(900), "reset should avoid a past target")
    }

    private static func testMultipleTimersDoNotInterfere() {
        let shortTimer = makeTimer(duration: 600)
        let longTimer = makeTimer(duration: 7_200)
        let later = start.addingTimeInterval(300)
        expect(
            abs(TimerLogic.remaining(for: shortTimer, at: later) - 300) < 0.001,
            "short timer calculation"
        )
        expect(
            abs(TimerLogic.remaining(for: longTimer, at: later) - 6_900) < 0.001,
            "long timer calculation"
        )
    }

    private static func testPersistenceRoundTripPreservesTimerAndSelection() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerCoreTest-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: directory.appendingPathComponent("timers.json"))
        let timer = makeTimer(duration: 3_600)
        let snapshot = TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id)

        do {
            try store.save(snapshot)
            let loaded = try store.load()
            expect(loaded == snapshot, "persistence should preserve timer data")
            expect(loaded.selectedTimerID == timer.id, "persistence should preserve selected timer")
        } catch {
            fputs("FAIL: persistence round trip threw \(error)\n", stderr)
            exit(1)
        }

        try? FileManager.default.removeItem(at: directory)
    }

    private static func testMenuBarFormattingPrecision() {
        expect(TimeFormatter.menuCountdown(2 * 86_400) == "2d 00h", "two-day menu format")
        expect(TimeFormatter.menuCountdown(2 * 3_600 + 14 * 60 + 37) == "02:14", "hour menu format")
        expect(TimeFormatter.menuCountdown(58 * 60 + 37) == "58:37", "minute menu format")
        expect(TimeFormatter.menuCountdown(9 * 60 + 42) == "09:42", "warning minute format")
        expect(TimeFormatter.menuCountdown(-1) == "00:00", "negative format should clamp")

        let named = TimerItem(
            name: "面試",
            createdAt: start,
            kind: .duration,
            originalDuration: 2 * 3_600 + 14 * 60 + 37,
            targetEndDate: start.addingTimeInterval(2 * 3_600 + 14 * 60 + 37),
            remainingDuration: 2 * 3_600 + 14 * 60 + 37
        )
        expect(
            TimeFormatter.menuBarTitle(for: named, at: start, format: .nameAndTime) == "面試 02:14",
            "named menu format"
        )

        var completed = makeTimer(duration: 60)
        completed.state = .completed
        expect(
            TimeFormatter.menuBarTitle(for: completed, at: start, format: .timeOnly) == "✓ 完成",
            "completed menu format"
        )
    }

    private static func testDeleteSelectedTimerChoosesAnotherOrNil() {
        let first = makeTimer(duration: 600)
        let second = makeTimer(duration: 1_200)
        let afterFirstDelete = TimerCollectionLogic.deletingTimer(
            id: first.id,
            from: [first, second],
            selectedTimerID: first.id
        )

        expect(afterFirstDelete.timers.count == 1, "delete should remove one timer")
        expect(afterFirstDelete.selectedTimerID == second.id, "delete should select remaining timer")

        let afterLastDelete = TimerCollectionLogic.deletingTimer(
            id: second.id,
            from: afterFirstDelete.timers,
            selectedTimerID: afterFirstDelete.selectedTimerID
        )
        expect(afterLastDelete.timers.isEmpty, "delete should support the last timer")
        expect(afterLastDelete.selectedTimerID == nil, "last delete should clear selection")
    }

    private static func testPausePersistenceFreezesRemainingDuration() {
        var timer = makeTimer(duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        expect(TimerLogic.pause(&timer, at: pausedAt), "pause for persistence should succeed")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerPause-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: directory.appendingPathComponent("timers.json"))
        do {
            try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
            let loaded = try store.load().timers[0]
            expect(loaded.state == .paused, "paused state should persist")
            expect(
                abs(TimerLogic.remaining(for: loaded, at: pausedAt.addingTimeInterval(1_200)) - 3_000) < 0.001,
                "paused remaining duration should stay frozen"
            )
        } catch {
            fail("pause persistence threw \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func testCompletedPersistenceKeepsCompletedState() {
        var timer = makeTimer(duration: 60)
        expect(TimerLogic.synchronize(&timer, at: start.addingTimeInterval(60)), "completion should succeed")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerCompleted-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: directory.appendingPathComponent("timers.json"))
        do {
            try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
            let loaded = try store.load().timers[0]
            expect(loaded.state == .completed, "completed state should persist")
            expect(loaded.remainingDuration == 0, "completed duration should stay zero")
        } catch {
            fail("completed persistence threw \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func testLongTimerFormattingDoesNotOverflow() {
        let oneHundredHours = 100 * 3_600.0
        expect(TimeFormatter.menuCountdown(oneHundredHours) == "4d 04h", "100-hour menu format")
        expect(TimeFormatter.detailCountdown(oneHundredHours) == "4d 04h 00m", "100-hour detail format")
    }

    private static func testTimerStoreHandlesMissingAndCorruptJSON() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerStore-\(UUID().uuidString)", isDirectory: true)
        let missingURL = directory.appendingPathComponent("missing.json")
        let missingStore = TimerStore(fileURL: missingURL)
        do {
            let missingSnapshot = try missingStore.load()
            expect(missingSnapshot == .empty, "missing JSON should mean no timers")
        } catch {
            fail("missing JSON should not throw: \(error)")
        }

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not-json".utf8).write(to: corruptURL)
            do {
                _ = try TimerStore(fileURL: corruptURL).load()
                fail("corrupt JSON should throw for TimerManager fallback")
            } catch {
                // Expected: TimerManager catches this and starts empty.
            }
        } catch {
            fail("corrupt JSON setup threw: \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func testScheduledFutureStartHasZeroProgressAndWaitingPhase() {
        let scheduledStart = start.addingTimeInterval(3_600)
        let timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)
        expect(TimerLogic.phase(for: timer, at: start) == .scheduled, "future scheduled timer phase")
        expect(
            abs(TimerLogic.timeUntilStart(for: timer, at: start) - 3_600) < 0.001,
            "future scheduled timer start countdown"
        )
        expect(TimerLogic.remaining(for: timer, at: start) == 0, "future scheduled timer has no duration remaining")
        expect(TimerLogic.progress(for: timer, at: start) == 0, "future scheduled progress should be zero")
        expect(TimerLogic.remainingProgress(for: timer, at: start) == 1, "future scheduled remaining progress")
    }

    private static func testScheduledActiveProgressIsTwentyFivePercent() {
        let timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let now = start.addingTimeInterval(2 * 86_400)
        expect(TimerLogic.phase(for: timer, at: now) == .running, "scheduled active phase")
        expect(abs(TimerLogic.progress(for: timer, at: now) - 0.25) < 0.001, "scheduled active progress")
        expect(abs(TimerLogic.remainingProgress(for: timer, at: now) - 0.75) < 0.001, "scheduled active remaining")
    }

    private static func testScheduledCompletedProgressIsClamped() {
        var timer = makeScheduledTimer(startDate: start.addingTimeInterval(-8 * 86_400), duration: 7 * 86_400)
        expect(TimerLogic.synchronize(&timer, at: start), "scheduled completion transition")
        expect(TimerLogic.phase(for: timer, at: start) == .completed, "scheduled completed phase")
        expect(TimerLogic.progress(for: timer, at: start) == 1, "scheduled progress should clamp to one")
        expect(TimerLogic.remainingProgress(for: timer, at: start) == 0, "scheduled remaining should clamp to zero")
        expect(TimerLogic.remaining(for: timer, at: start) == 0, "scheduled completed duration")
    }

    private static func testScheduledMidpointIsFiftyPercent() {
        let timer = makeScheduledTimer(startDate: start, duration: 7 * 86_400)
        let midpoint = start.addingTimeInterval(3.5 * 86_400)
        expect(abs(TimerLogic.progress(for: timer, at: midpoint) - 0.5) < 0.001, "scheduled midpoint progress")
        expect(abs(TimerLogic.remainingProgress(for: timer, at: midpoint) - 0.5) < 0.001, "scheduled midpoint remaining")
        expect(TimeFormatter.elapsedPercentageText(for: timer, at: midpoint) == "50.00%", "elapsed percentage text")
        expect(TimeFormatter.remainingPercentageText(for: timer, at: midpoint) == "50.00%", "remaining percentage text")
    }

    private static func testScheduledPauseResumePreservesProgress() {
        var timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let pauseAt = start.addingTimeInterval(2 * 86_400)
        let resumeAt = pauseAt.addingTimeInterval(3 * 86_400)
        expect(TimerLogic.pause(&timer, at: pauseAt), "scheduled pause")
        expect(TimerLogic.phase(for: timer, at: resumeAt) == .paused, "scheduled paused phase")
        expect(abs(TimerLogic.progress(for: timer, at: resumeAt) - 0.25) < 0.001, "paused scheduled progress")
        expect(TimerLogic.resume(&timer, at: resumeAt), "scheduled resume")
        expect(abs(TimerLogic.progress(for: timer, at: resumeAt) - 0.25) < 0.001, "resumed scheduled progress")
        expect(timer.targetEndDate == resumeAt.addingTimeInterval(6 * 86_400), "resumed scheduled target")
    }

    private static func testScheduledPersistencePreservesSchedule() {
        let scheduledStart = start.addingTimeInterval(3_600)
        let timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerScheduled-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: directory.appendingPathComponent("timers.json"))

        do {
            try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
            let loaded = try store.load().timers[0]
            expect(loaded.startDate == timer.startDate, "scheduled start persistence")
            expect(loaded.originalStartDate == timer.originalStartDate, "original scheduled start persistence")
            expect(loaded.originalDuration == timer.originalDuration, "scheduled duration persistence")
            expect(loaded.targetEndDate == timer.targetEndDate, "scheduled end persistence")
            expect(TimerLogic.progress(for: loaded, at: start) == 0, "persisted future scheduled progress")
        } catch {
            fail("scheduled persistence threw \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func testScheduledResetRestoresOriginalPastSchedule() {
        let scheduledStart = start.addingTimeInterval(-8 * 86_400)
        var timer = makeScheduledTimer(startDate: scheduledStart, duration: 7 * 86_400)
        TimerLogic.reset(&timer, at: start)
        expect(timer.startDate == scheduledStart, "scheduled reset start")
        expect(timer.targetEndDate == scheduledStart.addingTimeInterval(7 * 86_400), "scheduled reset end")
        expect(timer.state == .completed, "past scheduled reset stays completed")
        expect(timer.remainingDuration == 0, "past scheduled reset remaining")
    }

    private static func testRescheduleRunningScheduledTimerReplacesSchedule() {
        var timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let newStart = start.addingTimeInterval(3_600)
        let newDuration = 2 * 86_400.0
        let now = start.addingTimeInterval(600)

        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: newDuration,
            at: now
        ), "running scheduled reschedule")
        expect(timer.originalStartDate == newStart, "reschedule original start")
        expect(timer.startDate == newStart, "reschedule effective start")
        expect(timer.originalDuration == newDuration, "reschedule duration")
        expect(timer.targetEndDate == newStart.addingTimeInterval(newDuration), "reschedule target")
        expect(timer.state == .running, "rescheduled timer state")
        expect(TimerLogic.phase(for: timer, at: now) == .scheduled, "rescheduled future phase")
        expect(timer.remainingDuration == newDuration, "rescheduled future remaining")
    }

    private static func testRescheduleActiveScheduledTimerUsesNewProgress() {
        var timer = makeScheduledTimer(startDate: start, duration: 8 * 86_400)
        let newStart = start.addingTimeInterval(-600)
        let newDuration = 3_600.0

        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: newDuration,
            at: start
        ), "active scheduled reschedule")
        expect(TimerLogic.phase(for: timer, at: start) == .running, "rescheduled active phase")
        expect(abs(TimerLogic.progress(for: timer, at: start) - (1.0 / 6.0)) < 0.001, "rescheduled progress")
        expect(timer.remainingDuration == 3_000, "rescheduled active remaining")
    }

    private static func testReschedulePausedTimerClearsPausedSnapshot() {
        var timer = makeScheduledTimer(startDate: start, duration: 3_600)
        let pausedAt = start.addingTimeInterval(600)
        let newStart = start.addingTimeInterval(7_200)

        expect(TimerLogic.pause(&timer, at: pausedAt), "scheduled pause before reschedule")
        timer.completionNotificationAttempted = true
        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: 1_800,
            at: pausedAt
        ), "paused scheduled reschedule")
        expect(timer.state == .running, "reschedule clears paused state")
        expect(!timer.completionNotificationAttempted, "reschedule clears notification attempt")
        expect(TimerLogic.phase(for: timer, at: pausedAt) == .scheduled, "rescheduled paused future phase")
        expect(timer.remainingDuration == 1_800, "rescheduled paused remaining")
    }

    private static func testRescheduleCompletedTimerCreatesNewSchedule() {
        var timer = makeScheduledTimer(startDate: start.addingTimeInterval(-3_600), duration: 1_800)
        expect(TimerLogic.synchronize(&timer, at: start), "scheduled completion before reschedule")
        timer.completionNotificationAttempted = true
        let newStart = start.addingTimeInterval(600)

        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: 1_800,
            at: start
        ), "completed scheduled reschedule")
        expect(timer.state == .running, "reschedule clears completed state")
        expect(!timer.completionNotificationAttempted, "completed reschedule clears notification attempt")
        expect(TimerLogic.phase(for: timer, at: start) == .scheduled, "completed reschedule future phase")
        expect(timer.remainingDuration == 1_800, "completed reschedule remaining")
    }

    private static func testReschedulePastScheduleCompletesImmediately() {
        var timer = makeScheduledTimer(startDate: start, duration: 3_600)
        let newStart = start.addingTimeInterval(-7_200)

        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: 3_600,
            at: start
        ), "past scheduled reschedule")
        expect(timer.state == .completed, "past reschedule completes")
        expect(TimerLogic.phase(for: timer, at: start) == .completed, "past reschedule phase")
        expect(timer.remainingDuration == 0, "past reschedule remaining")
    }

    private static func testRescheduledSchedulePersistenceRoundTrip() {
        var timer = makeScheduledTimer(startDate: start, duration: 3_600)
        let newStart = start.addingTimeInterval(7_200)
        expect(TimerLogic.reschedule(
            &timer,
            startDate: newStart,
            duration: 7_200,
            at: start
        ), "reschedule persistence setup")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerReschedule-\(UUID().uuidString)", isDirectory: true)
        let store = TimerStore(fileURL: directory.appendingPathComponent("timers.json"))
        do {
            try store.save(TimerStoreSnapshot(timers: [timer], selectedTimerID: timer.id))
            let loaded = try store.load().timers[0]
            expect(loaded.originalStartDate == newStart, "rescheduled original start persistence")
            expect(loaded.startDate == newStart, "rescheduled start persistence")
            expect(loaded.originalDuration == 7_200, "rescheduled duration persistence")
            expect(loaded.targetEndDate == newStart.addingTimeInterval(7_200), "rescheduled target persistence")
            expect(loaded.state == .running, "rescheduled state persistence")
        } catch {
            fail("reschedule persistence threw \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func testV1JSONMigrationDefaultsStartDateFromCreatedAt() {
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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTimerMigration-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("timers.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try legacyJSON.data(using: .utf8)!.write(to: url)
            let loaded = try TimerStore(fileURL: url).load().timers[0]
            expect(loaded.startDate == loaded.createdAt, "V1 migration start date")
            expect(loaded.originalStartDate == nil, "V1 migration original schedule is nil")
            expect(loaded.completionNotificationAttempted, "V1 notification migration")
        } catch {
            fail("V1 migration threw \(error)")
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func makeTimer(duration: TimeInterval) -> TimerItem {
        TimerItem(
            name: "測試",
            createdAt: start,
            kind: .duration,
            originalDuration: duration,
            targetEndDate: start.addingTimeInterval(duration),
            remainingDuration: duration
        )
    }

    private static func makeScheduledTimer(startDate: Date, duration: TimeInterval) -> TimerItem {
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
