import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var timerManager: TimerManager

    var body: some View {
        Form {
            Section("一般") {
                Toggle(
                    "登入時自動啟動",
                    isOn: Binding(
                        get: { timerManager.launchAtLoginEnabled },
                        set: { timerManager.setLaunchAtLogin($0) }
                    )
                )

                Text("目前狀態：\(timerManager.launchAtLoginStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let settingsError = timerManager.settingsError {
                    Text(settingsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu Bar 顯示格式") {
                Picker(
                    "格式",
                    selection: Binding(
                        get: { timerManager.menuBarFormat },
                        set: { timerManager.setMenuBarFormat($0) }
                    )
                ) {
                    ForEach(MenuBarDisplayFormat.allCases) { format in
                        Text("\(format.title)（\(format.example)）")
                            .tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("通知") {
                Text("Timer 第一次完成時，App 會請求 macOS 通知權限。每個 Timer 只會嘗試送出一次完成通知。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("資料") {
                Text("Timer 儲存在本機 Application Support 的 JSON 檔案中，不會上傳或與其他 App 同步。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 350)
        .padding(.top, 8)
    }
}
