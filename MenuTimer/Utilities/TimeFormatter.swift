import Foundation

enum MenuBarDisplayFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case timeOnly
    case nameAndTime
    case percentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeOnly:
            return "只顯示時間"
        case .nameAndTime:
            return "名稱 + 時間"
        case .percentage:
            return "百分比"
        }
    }

    var example: String {
        switch self {
        case .timeOnly:
            return "02:14"
        case .nameAndTime:
            return "面試 02:14"
        case .percentage:
            return "68%"
        }
    }
}

enum TimeFormatter {
    static func wholeSeconds(_ duration: TimeInterval) -> Int {
        guard duration.isFinite else {
            return 0
        }
        return max(0, Int(duration.rounded(.down)))
    }

    /// Main detail display. It retains seconds for durations shorter than a
    /// day and uses a compact day form for very long timers.
    static func detailCountdown(_ duration: TimeInterval) -> String {
        let total = wholeSeconds(duration)
        let days = total / 86_400
        let remainderAfterDays = total % 86_400
        let hours = remainderAfterDays / 3_600
        let minutes = (remainderAfterDays % 3_600) / 60
        let seconds = remainderAfterDays % 60

        if days > 0 {
            return String(format: "%dd %02dh %02dm", days, hours, minutes)
        }

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Menu Bar display. It is intentionally shorter than the detail view.
    static func menuCountdown(_ duration: TimeInterval) -> String {
        let total = wholeSeconds(duration)
        let days = total / 86_400
        if days > 0 {
            let hours = (total % 86_400) / 3_600
            return String(format: "%dd %02dh", days, hours)
        }

        let hours = total / 3_600
        if hours > 0 {
            let minutes = (total % 3_600) / 60
            return String(format: "%02d:%02d", hours, minutes)
        }

        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func progressPercent(for timer: TimerItem, at now: Date) -> Int {
        Int((TimerLogic.progress(for: timer, at: now) * 100).rounded())
    }

    static func elapsedPercentageText(for timer: TimerItem, at now: Date) -> String {
        percentageText(TimerLogic.progress(for: timer, at: now) * 100)
    }

    static func remainingPercentageText(for timer: TimerItem, at now: Date) -> String {
        percentageText(TimerLogic.remainingProgress(for: timer, at: now) * 100)
    }

    static func percentageText(_ percentage: Double) -> String {
        String(format: "%.2f%%", min(100, max(0, percentage)))
    }

    static func truncatedName(_ name: String, maxCharacters: Int = 12) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxCharacters else {
            return normalized
        }
        return String(normalized.prefix(max(1, maxCharacters - 1))) + "…"
    }

    static func menuBarTitle(
        for timer: TimerItem?,
        at now: Date,
        format: MenuBarDisplayFormat
    ) -> String {
        guard let timer else {
            return "⏱"
        }

        let phase = TimerLogic.phase(for: timer, at: now)
        guard phase != .completed else {
            return "✓ 完成"
        }

        if phase == .scheduled {
            let untilStart = menuCountdown(TimerLogic.timeUntilStart(for: timer, at: now))
            switch format {
            case .timeOnly:
                return "⏱ " + untilStart + "後開始"
            case .nameAndTime:
                return truncatedName(timer.name) + " " + untilStart + "後開始"
            case .percentage:
                return "等待中"
            }
        }

        let remaining = TimerLogic.remaining(for: timer, at: now)
        let prefix = remaining < 600 ? "⚠︎" : "⏱"

        switch format {
        case .timeOnly:
            return prefix + " " + menuCountdown(remaining)
        case .nameAndTime:
            let warningPrefix = remaining < 600 ? "⚠︎ " : ""
            return warningPrefix + truncatedName(timer.name) + " " + menuCountdown(remaining)
        case .percentage:
            let warningPrefix = remaining < 600 ? "⚠︎ " : ""
            return warningPrefix + String(progressPercent(for: timer, at: now)) + "%"
        }
    }

    static func startDateText(for timer: TimerItem) -> String {
        timer.scheduleStartDate.formatted(date: .abbreviated, time: .shortened)
    }

    static func endDateText(for timer: TimerItem) -> String {
        guard let targetEndDate = timer.targetEndDate else {
            return "未設定"
        }

        if Calendar.current.isDateInToday(targetEndDate) {
            return "今天 " + targetEndDate.formatted(date: .omitted, time: .shortened)
        }

        if Calendar.current.isDateInTomorrow(targetEndDate) {
            return "明天 " + targetEndDate.formatted(date: .omitted, time: .shortened)
        }

        return targetEndDate.formatted(date: .abbreviated, time: .shortened)
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let total = wholeSeconds(duration)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        var parts: [String] = []

        if days > 0 {
            parts.append("\(days) 天")
        }
        if hours > 0 {
            parts.append("\(hours) 小時")
        }
        if minutes > 0 || parts.isEmpty {
            parts.append("\(minutes) 分鐘")
        }
        return parts.joined(separator: " ")
    }
}
