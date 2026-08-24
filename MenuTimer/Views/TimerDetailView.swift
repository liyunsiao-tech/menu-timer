import SwiftUI

struct TimerDetailView: View {
    @EnvironmentObject private var timerManager: TimerManager
    let timerID: UUID
    let onEditScheduledTimer: () -> Void

    var body: some View {
        if let timer = timerManager.timer(with: timerID) {
            let phase = timerManager.phase(for: timer)
            let progress = timerManager.progress(for: timer)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(timer.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(phase.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(
                    TimeFormatter.detailCountdown(
                        phase == .scheduled
                            ? timerManager.timeUntilStart(for: timer)
                            : timerManager.remaining(for: timer)
                    )
                )
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(phase == .scheduled ? "距開始" : "剩餘時間")

                Text(phase == .scheduled ? "距開始" : "剩餘時間")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .accessibilityLabel("Timer 進度")

                HStack {
                    Text("已過 (TimeFormatter.elapsedPercentageText(for: timer, at: timerManager.now))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("剩餘 (TimeFormatter.remainingPercentageText(for: timer, at: timerManager.now))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    infoRow("開始時間", value: TimeFormatter.startDateText(for: timer))
                    infoRow("結束時間", value: TimeFormatter.endDateText(for: timer))
                    infoRow("總時長", value: TimeFormatter.durationText(timer.originalDuration))
                }
                .font(.caption)

                HStack(spacing: 8) {
                    stateActionButton(for: timer, phase: phase)

                    if phase != .completed {
                        if timer.kind == .scheduledDuration {
                            Button {
                                onEditScheduledTimer()
                            } label: {
                                Label("編輯排程", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                timerManager.resetTimer(id: timer.id)
                            } label: {
                                Label("重設", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button(role: .destructive) {
                        timerManager.deleteTimer(id: timer.id)
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func stateActionButton(for timer: TimerItem, phase: TimerPhase) -> some View {
        switch phase {
        case .scheduled:
            Label("尚未開始", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .running:
            Button {
                timerManager.pauseTimer(id: timer.id)
            } label: {
                Label("暫停", systemImage: "pause.fill")
            }
            .buttonStyle(.borderedProminent)

        case .paused:
            Button {
                timerManager.resumeTimer(id: timer.id)
            } label: {
                Label("繼續", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

        case .completed:
            if timer.kind == .scheduledDuration {
                Button {
                    onEditScheduledTimer()
                } label: {
                    Label("編輯排程", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    timerManager.resetTimer(id: timer.id)
                } label: {
                    Label("重新開始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
