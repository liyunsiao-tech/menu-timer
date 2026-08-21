import SwiftUI

struct TimerListView: View {
    @EnvironmentObject private var timerManager: TimerManager
    let timerIDs: [UUID]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !timerIDs.isEmpty {
                Text("其他 Timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(timerIDs, id: \.self) { timerID in
                if let timer = timerManager.timer(with: timerID) {
                    let phase = timerManager.phase(for: timer)
                    Button {
                        timerManager.selectTimer(id: timer.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: phase == .completed ? "checkmark.circle" : "timer")
                                .foregroundStyle(phase == .completed ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(timer.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(statusText(for: timer, phase: phase))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            if phase == .paused {
                                Image(systemName: "pause.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }

            if timerIDs.isEmpty {
                Text("沒有其他 Timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(for timer: TimerItem, phase: TimerPhase) -> String {
        switch phase {
        case .scheduled:
            return "(TimeFormatter.menuCountdown(timerManager.timeUntilStart(for: timer)))後開始"
        case .running:
            return TimeFormatter.menuCountdown(timerManager.remaining(for: timer))
        case .paused:
            return "暫停 (TimeFormatter.menuCountdown(timerManager.remaining(for: timer)))"
        case .completed:
            return "完成"
        }
    }
}
