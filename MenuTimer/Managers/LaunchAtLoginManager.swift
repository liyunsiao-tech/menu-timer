import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已啟用"
        case .requiresApproval:
            return "需要系統核准"
        case .notRegistered:
            return "未啟用"
        case .notFound:
            return "找不到登入項目"
        @unknown default:
            return "狀態未知"
        }
    }
}
