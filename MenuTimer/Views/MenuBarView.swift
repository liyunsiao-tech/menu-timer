import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var timerManager: TimerManager
    @State private var isPresentingAddTimer = false

    private var otherTimerIDs: [UUID] {
        timerManager.timers
            .filter { $0.id != timerManager.selectedTimerID }
            .map(\.id)
    }

    var body: some View {
        Group {
            if isPresentingAddTimer {
                // Keep the form in the same MenuBarExtra window. A nested
                // sheet gives menu-bar content a second presentation layer
                // whose controls can dismiss the panel unexpectedly.
                AddTimerView(isPresented: $isPresentingAddTimer)
            } else {
                mainPanel
            }
        }
        .padding(14)
        .frame(width: 390)
        .onAppear {
            timerManager.refresh()
        }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedTimer = timerManager.selectedTimer {
                TimerDetailView(timerID: selectedTimer.id)
            } else {
                EmptyTimerView()
            }

            Divider()
                .padding(.vertical, 10)

            TimerListView(timerIDs: otherTimerIDs)

            Divider()
                .padding(.vertical, 10)

            HStack {
                Button {
                    isPresentingAddTimer = true
                } label: {
                    Label("新增 Timer", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                SettingsLink {
                    Label("設定", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("開啟設定")
            }

            if let persistenceError = timerManager.persistenceError {
                Text(persistenceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.vertical, 8)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 MenuTimer", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyTimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("還沒有 Timer", systemImage: "timer")
                .font(.headline)
            Text("建立一個 Timer 後，它會在 Menu Bar 持續顯示。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
