import SwiftUI

struct AddTimerView: View {
    @EnvironmentObject private var timerManager: TimerManager
    @Binding private var isPresented: Bool

    @State private var timerKind: TimerKind = .duration
    @State private var name = ""
    @State private var hoursText = "0"
    @State private var minutesText = "30"
    @State private var endDate = Date().addingTimeInterval(30 * 60)
    @State private var startDate = Date().addingTimeInterval(5 * 60)
    @State private var scheduledDays = 0
    @State private var scheduledHours = 0
    @State private var scheduledMinutes = 30
    @State private var validationMessage: String?

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("新增 Timer")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            TextField("名稱，例如：面試", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("模式", selection: $timerKind) {
                ForEach(TimerKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)

            switch timerKind {
            case .duration:
                durationSection
            case .endDate:
                endDateSection
            case .scheduledDuration:
                scheduledDurationSection
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("建立") {
                    createTimer()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("持續時間")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                TextField("小時", text: $hoursText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("小時")
                    .foregroundStyle(.secondary)
                TextField("分鐘", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("分鐘")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                presetButton(title: "30 分鐘", hours: 0, minutes: 30)
                presetButton(title: "1 小時", hours: 1, minutes: 0)
                presetButton(title: "4 小時", hours: 4, minutes: 0)
                presetButton(title: "8 小時", hours: 8, minutes: 0)
                presetButton(title: "24 小時", hours: 24, minutes: 0)
            }
        }
    }

    private var endDateSection: some View {
        DatePicker(
            "結束時間",
            selection: $endDate,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.field)
    }

    private var scheduledDurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
    }

    private func presetButton(title: String, hours: Int, minutes: Int) -> some View {
        Button(title) {
            hoursText = String(hours)
            minutesText = String(minutes)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func createTimer() {
        validationMessage = nil

        do {
            switch timerKind {
            case .duration:
                guard let hours = Int(hoursText), let minutes = Int(minutesText),
                      hours >= 0, minutes >= 0 else {
                    throw TimerCreationError.invalidDuration
                }
                let duration = TimeInterval(hours) * 3_600 + TimeInterval(minutes) * 60
                try timerManager.createDurationTimer(name: name, duration: duration)

            case .endDate:
                try timerManager.createEndDateTimer(name: name, endDate: endDate)

            case .scheduledDuration:
                let duration = TimeInterval(scheduledDays) * 86_400
                    + TimeInterval(scheduledHours) * 3_600
                    + TimeInterval(scheduledMinutes) * 60
                try timerManager.createScheduledDurationTimer(
                    name: name,
                    startDate: startDate,
                    duration: duration
                )
            }
            isPresented = false
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
