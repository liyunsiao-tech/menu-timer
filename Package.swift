// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MenuTimerCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MenuTimerCore", targets: ["MenuTimerCore"]),
        .executable(name: "MenuTimerCoreTestRunner", targets: ["MenuTimerCoreTestRunner"])
    ],
    targets: [
        // The full application is defined by MenuTimer.xcodeproj. This small
        // package target intentionally exposes the Foundation-only core so it
        // can be tested with the command-line runner even on a machine
        // without Xcode.app.
        .target(
            name: "MenuTimerCore",
            path: "MenuTimer",
            exclude: [
                "MenuTimerApp.swift",
                "Managers/NotificationManager.swift",
                "Managers/LaunchAtLoginManager.swift",
                "Managers/TimerManager.swift",
                "Assets.xcassets",
                "Views"
            ],
            sources: [
                "Models/TimerItem.swift",
                "Managers/TimerStore.swift",
                "Utilities/TimerLogic.swift",
                "Utilities/TimeFormatter.swift"
            ]
        ),
        .executableTarget(
            name: "MenuTimerCoreTestRunner",
            dependencies: ["MenuTimerCore"],
            path: "Tests",
            sources: ["CoreTimerTestRunner.swift"]
        )
    ]
)
