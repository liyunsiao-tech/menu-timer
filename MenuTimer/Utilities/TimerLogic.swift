import Foundation

/// Pure time and state transitions for timers.
///
/// The functions intentionally receive `now` instead of reading the clock
/// internally. This makes sleep/wake behavior explicit and keeps the core
/// deterministic in unit tests.
enum TimerLogic {
    static let minimumDuration: TimeInterval = 1

    static func phase(for timer: TimerItem, at now: Date) -> TimerPhase {
        switch timer.state {
        case .completed:
            return .completed
        case .paused:
            return .paused
        case .running:
            if timer.kind == .scheduledDuration, now < timer.startDate {
                return .scheduled
            }

            if let targetEndDate = timer.targetEndDate, now >= targetEndDate {
                return .completed
            }
            return .running
        }
    }

    static func timeUntilStart(for timer: TimerItem, at now: Date) -> TimeInterval {
        guard phase(for: timer, at: now) == .scheduled else {
            return 0
        }
        return max(0, timer.startDate.timeIntervalSince(now))
    }

    static func remaining(for timer: TimerItem, at now: Date) -> TimeInterval {
        switch phase(for: timer, at: now) {
        case .scheduled, .completed:
            // A future scheduled timer has not consumed any of its duration.
            // Its start countdown is exposed separately by `timeUntilStart`.
            return 0
        case .running:
            guard let targetEndDate = timer.targetEndDate else {
                // Defensive fallback for old/corrupt data. A running timer
                // without a target must never display a negative value.
                return max(0, timer.remainingDuration)
            }
            return max(0, targetEndDate.timeIntervalSince(now))
        case .paused:
            return max(0, timer.remainingDuration)
        }
    }

    static func elapsedDuration(for timer: TimerItem, at now: Date) -> TimeInterval {
        let duration = max(0, timer.originalDuration)
        guard duration > 0 else { return 0 }

        switch phase(for: timer, at: now) {
        case .scheduled:
            return 0
        case .running:
            return min(duration, max(0, now.timeIntervalSince(timer.startDate)))
        case .paused:
            return min(duration, max(0, duration - timer.remainingDuration))
        case .completed:
            return duration
        }
    }

    /// Synchronizes a timer with a real timestamp.
    /// - Returns: `true` only when this call transitions a running timer to
    ///   completed. The caller can use this edge to send one notification.
    @discardableResult
    static func synchronize(_ timer: inout TimerItem, at now: Date) -> Bool {
        switch timer.state {
        case .running:
            if phase(for: timer, at: now) == .scheduled {
                timer.remainingDuration = max(0, timer.originalDuration)
                return false
            }

            let remaining = remaining(for: timer, at: now)
            timer.remainingDuration = remaining

            guard remaining <= 0 else {
                return false
            }

            timer.state = .completed
            timer.remainingDuration = 0
            return true

        case .paused:
            timer.remainingDuration = max(0, timer.remainingDuration)
            return false

        case .completed:
            timer.remainingDuration = 0
            return false
        }
    }

    /// Pauses using the true remaining duration at the supplied timestamp.
    /// A paused timer keeps a target date only as a useful display snapshot;
    /// it is ignored until resume rebuilds the target from the paused value.
    /// Scheduled timers that have not started cannot be paused.
    @discardableResult
    static func pause(_ timer: inout TimerItem, at now: Date) -> Bool {
        synchronize(&timer, at: now)
        guard phase(for: timer, at: now) == .running else {
            return false
        }

        let remaining = remaining(for: timer, at: now)
        guard remaining > 0 else {
            timer.state = .completed
            timer.remainingDuration = 0
            return false
        }

        timer.remainingDuration = remaining
        timer.targetEndDate = now.addingTimeInterval(remaining)
        timer.state = .paused
        return true
    }

    /// Resumes from the frozen paused duration, never from the old target date.
    /// The effective start moves so elapsed progress excludes the pause time;
    /// a scheduled timer's original start remains available for Reset/display.
    @discardableResult
    static func resume(_ timer: inout TimerItem, at now: Date) -> Bool {
        guard timer.state == .paused else {
            return false
        }

        let remaining = max(0, timer.remainingDuration)
        guard remaining > 0 else {
            timer.remainingDuration = 0
            timer.state = .completed
            return false
        }

        let elapsed = min(
            max(0, timer.originalDuration),
            max(0, timer.originalDuration - remaining)
        )
        timer.startDate = now.addingTimeInterval(-elapsed)
        timer.targetEndDate = now.addingTimeInterval(remaining)
        timer.state = .running
        return true
    }

    /// Restarts a normal timer from now. A scheduled-duration timer instead
    /// restores its original selected schedule, even when that schedule is in
    /// the past; it never silently moves the schedule to now.
    static func reset(_ timer: inout TimerItem, at now: Date) {
        let duration = max(TimerLogic.minimumDuration, timer.originalDuration)
        timer.completionNotificationAttempted = false

        if timer.kind == .scheduledDuration {
            let originalStart = timer.originalStartDate ?? timer.startDate
            let originalEnd = originalStart.addingTimeInterval(duration)
            timer.startDate = originalStart
            timer.targetEndDate = originalEnd
            timer.remainingDuration = max(0, originalEnd.timeIntervalSince(now))
            timer.state = now >= originalEnd ? .completed : .running
            return
        }

        timer.startDate = now
        timer.remainingDuration = duration
        timer.targetEndDate = now.addingTimeInterval(duration)
        timer.state = .running
    }

    static func progress(for timer: TimerItem, at now: Date) -> Double {
        guard timer.originalDuration > 0 else {
            return 1
        }

        let elapsed = elapsedDuration(for: timer, at: now)
        return min(1, max(0, elapsed / timer.originalDuration))
    }

    static func remainingProgress(for timer: TimerItem, at now: Date) -> Double {
        1 - progress(for: timer, at: now)
    }
}

struct TimerDeletionResult: Equatable, Sendable {
    let timers: [TimerItem]
    let selectedTimerID: UUID?
}

enum TimerCollectionLogic {
    /// Deletes one timer and deterministically chooses the first remaining
    /// timer when the selected timer was removed. This keeps selection behavior
    /// testable without involving SwiftUI or persistence.
    static func deletingTimer(
        id: UUID,
        from timers: [TimerItem],
        selectedTimerID: UUID?
    ) -> TimerDeletionResult {
        guard let deletedIndex = timers.firstIndex(where: { $0.id == id }) else {
            return TimerDeletionResult(timers: timers, selectedTimerID: selectedTimerID)
        }

        var updatedTimers = timers
        let wasSelected = selectedTimerID == id || updatedTimers[deletedIndex].isSelected
        updatedTimers.remove(at: deletedIndex)

        let nextSelectedID: UUID?
        if updatedTimers.isEmpty {
            nextSelectedID = nil
        } else if wasSelected {
            nextSelectedID = updatedTimers[0].id
        } else if let selectedTimerID,
                  updatedTimers.contains(where: { $0.id == selectedTimerID }) {
            nextSelectedID = selectedTimerID
        } else {
            nextSelectedID = updatedTimers[0].id
        }

        for index in updatedTimers.indices {
            updatedTimers[index].isSelected = updatedTimers[index].id == nextSelectedID
        }

        return TimerDeletionResult(
            timers: updatedTimers,
            selectedTimerID: nextSelectedID
        )
    }
}
