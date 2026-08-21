# MenuTimer

MenuTimer 是一個輕量、原生、只存在於 macOS Menu Bar 的離線倒數計時器。它使用 Swift、SwiftUI 與 `MenuBarExtra`，不使用 Electron、WebView、HTML 或 JavaScript，也不需要帳號、後端或雲端同步。

## Screenshot

> Screenshot placeholder：完成第一次 Xcode 執行後，可在此放入 Menu Bar 展開介面與設定視窗截圖。

## 系統需求

- Requires macOS 14 or later
- Xcode 15 或以上（建議使用目前支援的 Xcode）
- Swift 5.9 以上

Bundle Identifier：`tech.liyunsiao.MenuTimer`；Test target 使用 `tech.liyunsiao.MenuTimerTests`。

`MenuBarExtra` 與 `SMAppService` 都以 macOS 14 為最低部署目標。App 使用 `LSUIElement`，正常執行時不會在 Dock 顯示普通 App icon，也不需要主視窗。

## 功能

- 以持續時間建立 Timer：自訂小時/分鐘，並提供 30 分鐘、1/4/8/24 小時快捷選項
- 以指定日期與時間建立 Timer；過去的時間會被 UI 阻止
- 以指定開始日期/時間與天、小時、分鐘建立 Scheduled Duration Timer
- 多個 Timer 同時運作，並可切換目前選中的 Timer
- Pause、Resume、Reset、Delete
- Detail View 顯示已過百分比、剩餘百分比與原生 `ProgressView`
- Menu Bar 顯示目前選中 Timer 的時間、名稱 + 時間或百分比
- 超過 24 小時的精簡顯示、低於 10 分鐘的警示顯示，以及完成狀態
- 可從 Menu Bar 介面退出 MenuTimer
- macOS 原生 UserNotifications 完成通知，每個 Timer 只嘗試一次
- Light Mode / Dark Mode，以及 SF Symbols 原生控制項
- 登入時自動啟動設定（`SMAppService`）

## 用 Xcode Build / Run

1. 使用 Xcode 開啟 `MenuTimer.xcodeproj`。
2. 選擇 `MenuTimer` scheme 與一台本機 Mac 作為 Run Destination。
3. 使用 `Product > Build`（⌘B）編譯。
4. 使用 `Product > Run`（⌘R）啟動。
5. App 啟動後，從螢幕右上角 Menu Bar 的 `⏱` 項目開啟操作介面。
6. 在 `Product > Test`（⌘U）執行 `MenuTimerTests`。

也可以使用命令列執行 Debug Build：

```bash
xcodebuild \
  -project MenuTimer.xcodeproj \
  -scheme MenuTimer \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

未簽章的本機 Debug build 可能無法立即註冊登入時自動啟動服務；這是 `SMAppService` 的系統安全限制。App 會保留正常的官方 API 架構，不使用 Login Items hack。若 Toggle 失敗，請先以 Xcode 建立可識別的 App bundle，並依 macOS 顯示的系統設定核准提示處理。

## 命令列核心驗證

本專案另外提供 Foundation-only 的 Swift Package 核心與測試執行器，讓沒有完整 Xcode.app 的環境仍能驗證 Timer 計算：

```bash
swift run MenuTimerCoreTestRunner
```

它會驗證 running、pause、resume、completed、end-date reset、多 Timer、格式、選取刪除、paused/completed persistence、長時間與壞 JSON fallback。完整 UI、通知與 `SMAppService` 測試仍需要 Xcode 與 macOS App target。

## 架構

```text
MenuTimer/
├── MenuTimerApp.swift
├── Models/
│   └── TimerItem.swift
├── Managers/
│   ├── TimerManager.swift
│   ├── TimerStore.swift
│   ├── NotificationManager.swift
│   └── LaunchAtLoginManager.swift
├── Views/
│   ├── MenuBarView.swift
│   ├── TimerDetailView.swift
│   ├── TimerListView.swift
│   ├── AddTimerView.swift
│   └── SettingsView.swift
└── Utilities/
    ├── TimerLogic.swift
    └── TimeFormatter.swift
```

- `TimerItem`：Codable 的持久化資料模型，包含 UUID、名稱、建立時間、開始時間、原始排程開始時間、Timer 類型、原始總時長、目標結束時間、剩餘時間、狀態、選取狀態與通知旗標。
- `TimerLogic`：不依賴 UI 或系統時鐘的純時間狀態轉換，方便用固定 `Date` 做測試。
- `TimerManager`：管理多 Timer、選取狀態、刷新週期、CRUD、持久化與完成通知觸發。
- `TimerStore`：以原子寫入的 JSON 保存資料。
- Views：分離 Menu Bar 容器、目前 Timer 詳情、多 Timer 清單、新增流程與 Settings。

## Timer 核心計算

Timer 的時間模型保存：

```text
startDate
originalDuration
targetEndDate = startDate + originalDuration
```

Running Timer 的剩餘時間永遠計算為：

```text
max(0, targetEndDate - currentDate)
```

因此 App 卡頓、背景暫停、Mac 睡眠或重新開啟後，都會依實際時間重新對齊，而不是依賴每秒遞減的計數器。UI 更新週期會動態調整：剩餘小於一小時時每秒更新；剩餘大於等於一小時的 Timer 約每 30 秒更新；沒有 running Timer 時每 60 秒檢查一次。Menu Bar 顯示精度與此一致：大於等於一小時只顯示 `HH:mm`，小於一小時顯示 `mm:ss`，大於等於一天顯示 `Xd HHh`。

所有進度都由真實 `Date` 計算，並 clamp 在 `0...1`。尚未開始的 Scheduled Duration Timer 會顯示距開始時間，但進度固定為 `0%`；進行中使用 `now - startDate`，已完成固定為 `100%`。

Pause 會把當下的真實剩餘秒數寫入 `remainingDuration`。Resume 會建立：

```text
targetEndDate = currentDate + pausedRemainingDuration
```

Reset 會使用建立時保存的 `originalDuration`。一般 Duration 與 Absolute End Timer 會從現在重新開始；Scheduled Duration Timer 則恢復原始 `startDate` 與 `targetEndDate`。如果原始排程已經完整過去，Reset 後仍保持 completed，不會偷偷移到現在。

## Persistence

Timer 儲存在：

```text
~/Library/Application Support/MenuTimer/timers.json
```

本專案選用 Codable + JSON，而不是 SwiftData，原因是它可以支援 macOS 14 的部署目標、資料格式透明，且對少量 Timer 資料足夠可靠。檔案使用 ISO 8601 日期與 atomic write。V1 JSON 缺少 `startDate` 時會以 `createdAt` 作為相容的開始時間；舊的 `completionNotificationSent` 也會相容讀取。資料夾不存在時視為沒有 Timer；壞 JSON 會由 `TimerManager` 捕捉並以空白清單啟動。

- running Timer：重新載入後依新的 `Date()` 計算
- paused Timer：保留 pause 當下的剩餘時間
- completed Timer：保持 completed 與剩餘 0
- `selectedTimerID` 與每個 Timer 的選取旗標一併保存

## Notification permission

第一次需要完成通知時，`NotificationManager` 會檢查權限；若尚未決定，使用 `UNUserNotificationCenter` 請求 `.alert` 與 `.sound`。Timer 在完成邊緣會保存 `completionNotificationAttempted`，再非同步嘗試送出通知；這個欄位明確代表「最多嘗試一次」，不宣稱 macOS 一定成功顯示通知，因此每秒刷新或 App 重啟都不會反覆嘗試。

若使用者拒絕通知，Timer 仍會正常完成；通知不會以背景輪詢方式重複嘗試。

## 已知限制

- 本版本依賴絕對 `Date` 計算；若使用者手動大幅調整系統時間，倒數會依新的系統時間反映，這是時間戳記模型的預期行為。
- `SMAppService` 對未簽章或尚未經系統核准的 Debug App 可能回報 `requiresApproval` 或註冊失敗，需在正式簽章/可識別的 App bundle 上驗證。
- 使用者若在 macOS 通知設定中關閉通知，Timer 不會因此停止，但不會顯示完成通知。
- 目前沒有 iCloud、Web Timer、Widget、Live Activity、Pomodoro、統計、Todo 或行事曆功能，刻意維持第一版範圍。
- 完整 App build、XCTest 與 Menu Bar 行為需要安裝 Xcode.app；Swift Package 測試執行器只能覆蓋 Foundation-only 核心。

## 下一版最值得加入的功能

1. 更完整的 Timer 編輯與拖曳排序。
2. 可選的通知聲音與完成後自動選取策略。
3. 以 Xcode UI Test 驗證 Menu Bar popover、睡眠恢復與通知權限流程。
