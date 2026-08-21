import Foundation

/// The way a timer was created.
enum TimerKind: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case duration
    case endDate
    case scheduledDuration

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duration:
            return "從現在倒數"
        case .endDate:
            return "指定結束時間"
        case .scheduledDuration:
            return "指定開始 + 持續時間"
        }
    }
}

enum TimerState: String, Codable, CaseIterable, Sendable {
    case running
    case paused
    case completed

    var displayName: String {
        switch self {
        case .running:
            return "進行中"
        case .paused:
            return "已暫停"
        case .completed:
            return "已完成"
        }
    }
}

/// A time-derived phase. It is intentionally not persisted: the current
/// phase is derived from the persisted state, dates, and the supplied `now`.
enum TimerPhase: String, CaseIterable, Equatable, Sendable {
    case scheduled
    case running
    case paused
    case completed

    var displayName: String {
        switch self {
        case .scheduled:
            return "尚未開始"
        case .running:
            return "進行中"
        case .paused:
            return "已暫停"
        case .completed:
            return "已完成"
        }
    }
}

/// Persistent timer data.
///
/// `startDate`, `originalDuration`, and `targetEndDate` are the authoritative
/// schedule inputs. `remainingDuration` is a persisted snapshot for paused
/// and completed timers, and a recovery value for running timers. A scheduled
/// timer also preserves `originalStartDate` so Reset can restore the original
/// schedule after a pause/resume cycle.
struct TimerItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var startDate: Date
    let originalStartDate: Date?
    let kind: TimerKind
    let originalDuration: TimeInterval
    var targetEndDate: Date?
    var remainingDuration: TimeInterval
    var state: TimerState
    /// Means that this timer has had its one allowed notification attempt
    /// scheduled. It deliberately does not claim that macOS accepted the
    /// notification request; see NotificationManager for delivery handling.
    var completionNotificationAttempted: Bool
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        kind: TimerKind,
        originalDuration: TimeInterval,
        targetEndDate: Date?,
        remainingDuration: TimeInterval,
        state: TimerState = .running,
        completionNotificationAttempted: Bool = false,
        isSelected: Bool = false,
        startDate: Date? = nil,
        originalStartDate: Date? = nil
    ) {
        let resolvedStartDate = startDate ?? createdAt
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.startDate = resolvedStartDate
        self.originalStartDate = originalStartDate
            ?? (kind == .scheduledDuration ? resolvedStartDate : nil)
        self.kind = kind
        self.originalDuration = max(0, originalDuration)
        self.targetEndDate = targetEndDate
        self.remainingDuration = max(0, remainingDuration)
        self.state = state
        self.completionNotificationAttempted = completionNotificationAttempted
        self.isSelected = isSelected
    }

    /// The user-facing schedule start. For a scheduled timer this remains the
    /// original selected start even if Resume adjusted the effective start.
    var scheduleStartDate: Date {
        originalStartDate ?? startDate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case startDate
        case originalStartDate
        case kind
        case originalDuration
        case targetEndDate
        case remainingDuration
        case state
        case completionNotificationAttempted
        case legacyCompletionNotificationSent = "completionNotificationSent"
        case isSelected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.kind = try container.decode(TimerKind.self, forKey: .kind)
        self.originalDuration = max(0, try container.decode(TimeInterval.self, forKey: .originalDuration))

        // V1 did not persist startDate. Its creation timestamp is the only
        // compatible start for the existing duration and end-date kinds.
        let decodedStartDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
            ?? self.createdAt
        self.startDate = decodedStartDate
        self.originalStartDate = try container.decodeIfPresent(Date.self, forKey: .originalStartDate)
            ?? (self.kind == .scheduledDuration ? decodedStartDate : nil)
        self.targetEndDate = try container.decodeIfPresent(Date.self, forKey: .targetEndDate)
        self.remainingDuration = max(0, try container.decode(TimeInterval.self, forKey: .remainingDuration))
        self.state = try container.decode(TimerState.self, forKey: .state)
        self.completionNotificationAttempted = try container.decodeIfPresent(
            Bool.self,
            forKey: .completionNotificationAttempted
        ) ?? container.decodeIfPresent(Bool.self, forKey: .legacyCompletionNotificationSent) ?? false
        self.isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(originalStartDate, forKey: .originalStartDate)
        try container.encode(kind, forKey: .kind)
        try container.encode(originalDuration, forKey: .originalDuration)
        try container.encodeIfPresent(targetEndDate, forKey: .targetEndDate)
        try container.encode(remainingDuration, forKey: .remainingDuration)
        try container.encode(state, forKey: .state)
        try container.encode(completionNotificationAttempted, forKey: .completionNotificationAttempted)
        try container.encode(isSelected, forKey: .isSelected)
    }
}

struct TimerStoreSnapshot: Codable, Equatable, Sendable {
    var timers: [TimerItem]
    var selectedTimerID: UUID?

    static let empty = TimerStoreSnapshot(timers: [], selectedTimerID: nil)
}
