import Foundation

public final class EventLogStore {
    private let logURL: URL
    private let logsDirectory: URL
    private let encoder: JSONEncoder
    private var lastArchivedHourKey: String?
    private var lastArchivedModificationDate: Date?

    public init(dataDirectory: DataDirectory) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "events-\(formatter.string(from: Date())).jsonl"
        logsDirectory = dataDirectory.logs
        logURL = dataDirectory.logs.appendingPathComponent(filename)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(_ event: GameEvent) {
        guard let data = try? encoder.encode(event) else { return }
        guard let line = String(data: data, encoding: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } else {
                try Data((line + "\n").utf8).write(to: logURL, options: .atomic)
            }
        } catch {
            // Keep simulation resilient if log I/O fails.
        }
    }

    public var currentLogURL: URL { logURL }

    public func archiveCurrentLogIfNeededForCurrentHour() {
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "yyyyMMdd-HH"
        let hourKey = hourFormatter.string(from: Date())
        guard lastArchivedHourKey != hourKey else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: logURL.path) else { return }
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0 else { return }
        let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
        if let lastArchivedModificationDate, modified <= lastArchivedModificationDate {
            return
        }

        let archiveDir = logsDirectory.appendingPathComponent("archive", isDirectory: true)
        try? fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let zipURL = archiveDir.appendingPathComponent("events-\(hourKey).zip")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["zip", "-j", "-q", zipURL.path, logURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                lastArchivedHourKey = hourKey
                lastArchivedModificationDate = modified
            }
        } catch {
            // Ignore archiving failures; never block game loop.
        }
    }
}
