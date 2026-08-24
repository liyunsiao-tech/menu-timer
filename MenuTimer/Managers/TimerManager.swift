import Foundation
import SwiftUI

enum TimerCreationError: LocalizedError {
    case emptyName
    case invalidDuration
    case endDateInPast
    case scheduledDurationRequired

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "請輸入 Timer 名稱。"
        case .invalidDuration:
            return "持續時間必須大於 0。"
        case .endDateInPast:
            return "結束時間必須晚於現在。"
        case .scheduledDurationRequired:
            return "只有 Scheduled Duration 可以編輯排程。"
        }
    }
}

@MainActor
final class TimerManager: ObservableObject {
    static let menuBarFormatDefaultsKey = "MenuTimer.menuBarFormat"

    @Published private(set) var timers: [TimerItem] = []
    @Published private(set) var selectedTimerID: UUID?
    @Published private(set) var now = Date()
    @Published var menuBarFormat: MenuBarDisplayFormat {
        didSet {
            UserDefaults.standard.set(menuBarFormat.rawValue, forKey: Self.menuBarFormatDefaultsKey)
        }
    }
    @Published private(set) var launchAtLoginEnabled = false
    @Published var persistenceError: String? = nil
    @Published var settingsError: String? = nil

    private let store: TimerStore
    private let notificationManager: NotificationManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private var refreshTask: Task<Void, Never>?

    init(
        store: TimerStore = TimerStore(),
        notificationManager: NotificationManager? = nil,
        launchAtLoginManager: LaunchAtLoginManager? = nil
    ) {
        self.store = store
        self.notificationManager = notificationManager ?? NotificationManager()
        self.launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()

        let storedFormat = UserDefaults.standard.string(forKey: Self.menuBarFormatDefaultsKey)
            .flatMap(MenuBarDisplayFormat.init(rawValue:))
        self.menuBarFormat = storedFormat ?? .timeOnly

        var loadError: String?
        if let snapshot = try? store.load() {
            self.timers = snapshot.timers
            self.selectedTimerID = snapshot.selectedTimerID
        } else {
            self.timers = []
            self.selectedTimerID = nil
            loadError = "無法載入已保存的 Timer 資料；將以空白清單啟動。"
        }

        self.persistenceError = loadError
        self.launchAtLoginEnabled = self.launchAtLoginManager.isEnabled
        normalizeSelection()
        refresh()
        startRefreshLoop()
    }

    deinit {
        refreshTask?.cancel()
    }

    var selectedTimer: TimerItem? {
        guard let selectedTimerID else { return nil }
        return timers.first(where: { $0.id == selectedTimerID })
    }

    var menuBarTitle: String {
        TimeFormatter.menuBarTitle(for: selectedTimer, at: now, format: menuBarFormat)
    }

    var launchAtLoginStatus: String {
        launchAtLoginManager.statusDescription
    }

    func timer(with id: UUID) -> TimerItem? {
        timers.first(where: { $0.id == id })
    }

    func remaining(for timer: TimerItem) -> TimeInterval {
        TimerLogic.remaining(for: timer, at: now)
    }

    func timeUntilStart(for timer: TimerItem) -> TimeInterval {
        TimerLogic.timeUntilStart(for: timer, at: now)
    }

    func phase(for timer: TimerItem) -> TimerPhase {
        TimerLogic.phase(for: timer, at: now)
    }

    func progress(for timer: TimerItem) -> Double {
        TimerLogic.progress(for: timer, at: now)
    }

    func remainingProgress(for timer: TimerItem) -> Double {
        TimerLogic.remainingProgress(for: timer, at: now)
    }

    func selectTimer(id: UUID) {
        guard timers.contains(where: { $0.id == id }) else { return }
        setSelection(id)
        save()
    }

    @discardableResult
    func createDurationTimer(name: String, duration: TimeInterval) throws -> UUID {
        let start = Date()
        now = start
        let normalizedName = try normalizedName(name)
        guard duration >= TimerLogic.minimumDuration else {
            throw TimerCreationError.invalidDuration
        }

        let item = TimerItem(
            name: normalizedName,
            createdAt: start,
            kind: .duration,
            originalDuration: duration,
            targetEndDate: start.addingTimeInterval(duration),
            remainingDuration: duration,
            state: .running,
            isSelected: true,
            startDate: start
        )
        appendAndSelect(item)
        return item.id
    }

    @discardableResult
    func createEndDateTimer(name: String, endDate: Date) throws -> UUID {
        let start = Date()
        now = start
        let normalizedName = try normalizedName(name)
        let duration = endDate.timeIntervalSince(start)
        guard duration >= TimerLogic.minimumDuration else {
            throw TimerCreationError.endDateInPast
        }

        let item = TimerItem(
            name: normalizedName,
            createdAt: start,
            kind: .endDate,
            originalDuration: duration,
            targetEndDate: endDate,
            remainingDuration: duration,
            state: .running,
            isSelected: true,
            startDate: start
        )
        appendAndSelect(item)
        return item.id
    }

    @discardableResult
    func createScheduledDurationTimer(
        name: String,
        startDate: Date,
        duration: TimeInterval
    ) throws -> UUID {
        let createdAt = Date()
        let normalizedName = try normalizedName(name)
        guard duration >= TimerLogic.minimumDuration else {
            throw TimerCreationError.invalidDuration
        }

        let item = TimerItem(
            name: normalizedName,
            createdAt: createdAt,
            kind: .scheduledDuration,
            originalDuration: duration,
            targetEndDate: startDate.addingTimeInterval(duration),
            remainingDuration: duration,
            state: .running,
            isSelected: true,
            startDate: startDate,
            originalStartDate: startDate
        )
        now = createdAt
        appendAndSelect(item)
        return item.id
    }

    func updateScheduledDurationTimer(
        id: UUID,
        startDate: Date,
        duration: TimeInterval
    ) throws {
        let currentDate = Date()
        now = currentDate
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        guard timers[index].kind == .scheduledDuration else {
            throw TimerCreationError.scheduledDurationRequired
        }
        guard duration >= TimerLogic.minimumDuration else {
            throw TimerCreationError.invalidDuration
        }

        var item = timers[index]
        guard TimerLogic.reschedule(
            &item,
            startDate: startDate,
            duration: duration,
            at: currentDate
        ) else {
            throw TimerCreationError.scheduledDurationRequired
        }

        timers[index] = item
        save()
        startRefreshLoop()
    }

    func pauseTimer(id: UUID) {
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        var item = timers[index]
        guard TimerLogic.pause(&item, at: now) else {
            timers[index] = item
            save()
            return
        }
        timers[index] = item
        save()
        startRefreshLoop()
    }

    func resumeTimer(id: UUID) {
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        var item = timers[index]
        guard TimerLogic.resume(&item, at: now) else {
            timers[index] = item
            save()
            return
        }
        timers[index] = item
        save()
        startRefreshLoop()
    }

    func resetTimer(id: UUID) {
        let currentDate = Date()
        now = currentDate
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        var item = timers[index]
        TimerLogic.reset(&item, at: currentDate)
        timers[index] = item
        save()
        startRefreshLoop()
    }

    func deleteTimer(id: UUID) {
        guard timers.contains(where: { $0.id == id }) else { return }
        let deletion = TimerCollectionLogic.deletingTimer(
            id: id,
            from: timers,
            selectedTimerID: selectedTimerID
        )
        timers = deletion.timers
        selectedTimerID = deletion.selectedTimerID
        save()
        startRefreshLoop()
    }

    func setMenuBarFormat(_ format: MenuBarDisplayFormat) {
        menuBarFormat = format
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            settingsError = nil
        } catch {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            settingsError = "無法更新登入時自動啟動：\(error.localizedDescription)"
        }
    }

    /// Reconciles every running timer with a real wall-clock timestamp. This
    /// handles app relaunch, sleep/wake, and a delayed refresh without relying
    /// on a per-second decrement counter.
    func refresh() {
        let currentDate = Date()
        now = currentDate
        var changed = false
        var completedItems: [TimerItem] = []

        for index in timers.indices {
            var item = timers[index]
            let becameCompleted = TimerLogic.synchronize(&item, at: currentDate)

            if item != timers[index] {
                changed = true
                timers[index] = item
            }

            if becameCompleted &&
                !item.completionNotificationAttempted {
                // This is intentionally an "attempted" flag, not a delivery
                // success flag. Persisting it before the async call guarantees
                // that a denied/failed notification is not retried forever.
                item.completionNotificationAttempted = true
                timers[index] = item
                completedItems.append(item)
                changed = true
            }
        }

        if changed {
            save()
        }

        for item in completedItems {
            Task { @MainActor [notificationManager] in
                _ = await notificationManager.sendCompletionNotification(
                    timerID: item.id,
                    timerName: item.name
                )
            }
        }
    }

    private func normalizedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TimerCreationError.emptyName
        }

        // Keep the stored name readable while the menu-bar formatter applies
        // a much shorter display-only truncation.
        return String(trimmed.prefix(120))
    }

    private func appendAndSelect(_ item: TimerItem) {
        timers.append(item)
        setSelection(item.id)
        save()
        startRefreshLoop()
    }

    private func setSelection(_ id: UUID?) {
        selectedTimerID = id
        for index in timers.indices {
            timers[index].isSelected = timers[index].id == id
        }
    }

    private func normalizeSelection() {
        let candidate = selectedTimerID.flatMap { id in
            timers.contains(where: { $0.id == id }) ? id : nil
        } ?? timers.first(where: { $0.isSelected })?.id ?? timers.first?.id
        setSelection(candidate)
    }

    private func save() {
        do {
            let snapshot = TimerStoreSnapshot(
                timers: timers,
                selectedTimerID: selectedTimerID
            )
            try store.save(snapshot)
            persistenceError = nil
        } catch {
            persistenceError = "無法儲存 Timer：\(error.localizedDescription)"
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()

                let interval: UInt64
                let needsSecondRefresh = self.timers.contains { timer in
                    switch TimerLogic.phase(for: timer, at: self.now) {
                    case .running:
                        return TimerLogic.remaining(for: timer, at: self.now) < 3_600
                    case .scheduled:
                        return TimerLogic.timeUntilStart(for: timer, at: self.now) < 3_600
                    case .paused, .completed:
                        return false
                    }
                }
                if needsSecondRefresh {
                    interval = 1_000_000_000
                } else if self.timers.contains(where: {
                    let phase = TimerLogic.phase(for: $0, at: self.now)
                    return phase == .running || phase == .scheduled
                }) {
                    interval = 30_000_000_000
                } else {
                    interval = 60_000_000_000
                }

                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }
}
