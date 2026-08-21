import Foundation

enum TimerStoreError: LocalizedError {
    case unableToLocateApplicationSupport

    var errorDescription: String? {
        switch self {
        case .unableToLocateApplicationSupport:
            return "找不到 macOS Application Support 資料夾。"
        }
    }
}

final class TimerStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        self.fileURL = applicationSupport
            .appendingPathComponent("MenuTimer", isDirectory: true)
            .appendingPathComponent("timers.json", isDirectory: false)
    }

    func load() throws -> TimerStoreSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimerStoreSnapshot.self, from: data)
    }

    func save(_ snapshot: TimerStoreSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
