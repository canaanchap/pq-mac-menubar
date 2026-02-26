import Foundation

public struct DataDirectory {
    public let root: URL
    public let data: URL
    public let saves: URL
    public let logs: URL
    public let mods: URL

    public init(fileManager: FileManager = .default) throws {
        let home = fileManager.homeDirectoryForCurrentUser
        root = home.appendingPathComponent(".pq-menubar", isDirectory: true)
        data = root.appendingPathComponent("data", isDirectory: true)
        saves = root.appendingPathComponent("saves", isDirectory: true)
        logs = root.appendingPathComponent("logs", isDirectory: true)
        mods = root.appendingPathComponent("mods", isDirectory: true)

        for path in [root, data, saves, logs, mods] {
            try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        }
    }
}
