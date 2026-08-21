import SwiftUI

@main
@MainActor
struct MenuTimerApp: App {
    @StateObject private var timerManager = TimerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(timerManager)
        } label: {
            Text(timerManager.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(timerManager)
        }
    }
}
