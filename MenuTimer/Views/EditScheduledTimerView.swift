import SwiftUI

struct EditScheduledTimerView: View {
    @EnvironmentObject private var timerManager: TimerManager

    let timer: TimerItem
    let onDismiss: () -> Void

    @State private var startDate: Date
    @State private var scheduledDays: Int
    @State private var scheduledHours: Int
    @State private var scheduledMinutes: Int
    @State private var validationMessage: String?

    init(timer: TimerItem, onDismiss: @escaping () -> Void) {
        self.timer = timer
        self.onDismiss = onDismiss

        let totalMinutes = max(0, Int(timer.originalDuration / 60))
        _startDate = State(initialValue: timer.scheduleStartDate)
        _scheduledDays = State(initialValue: totalMinutes / (24 * 60))
        _scheduledHours = State(initialValue: (totalMinutes % (24 * 60)) / 60)
        _scheduledMinutes = State(initialValue: totalMinutes % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("編輯排程")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("取消") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text(timer.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            DatePicker(
                "開始時間",
                selection: $startDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)

            Text("持續時間")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $scheduledDays, in: 0...3_650) {
                    Text("\(scheduledDays) 天")
                        .frame(minWidth: 110, alignment: .leading)
                }
                Stepper(value: $scheduledHours, in: 0...23) {
                    Text("\(scheduledHours) 小時")
                        .frame(minWidth: 110, alignment: .leading)
                }
                Stepper(value: $scheduledMinutes, in: 0...59) {
                    Text("\(scheduledMinutes) 分鐘")
                        .frame(minWidth: 110, alignment: .leading)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("儲存") {
                    saveSchedule()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private var duration: TimeInterval {
        TimeInterval(scheduledDays) * 86_400
            + TimeInterval(scheduledHours) * 3_600
            + TimeInterval(scheduledMinutes) * 60
    }

    private func saveSchedule() {
        validationMessage = nil

        do {
            try timerManager.updateScheduledDurationTimer(
                id: timer.id,
                startDate: startDate,
                duration: duration
            )
            onDismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
