import Foundation
import PQCore

struct MultiplayerAccountProfile: Codable, Hashable {
    var accountId: String
    var email: String
    var publicName: String
    var wantsNews: Bool
    var verified: Bool
    var updatedAt: Date
}

struct MultiplayerSession: Codable, Hashable {
    var accountId: String
    var sessionToken: String
    var expiresAt: Date
    var issuedAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

struct MultiplayerRealmCache: Codable, Hashable {
    struct RealmSummary: Codable, Hashable {
        var realmId: String
        var name: String
        var status: String
        var supportsGuilds: Bool
    }

    var realms: [RealmSummary]
    var fetchedAt: Date
}

struct MultiplayerGuildCache: Codable, Hashable {
    var guildId: String
    var formalName: String
    var shortTag: String
    var alignmentCode: String
    var typeCode: String
    var motto: String
    var chiefCharacterId: String
    var memberCount: Int
    var fetchedAt: Date
}

struct MultiplayerCheckpointQueueItem: Codable, Hashable, Identifiable {
    var id: UUID
    var characterID: UUID
    var serverCharacterId: String
    var checkpointId: String
    var enqueuedAt: Date
    var attempts: Int
    var payload: Data

    init(
        id: UUID = UUID(),
        characterID: UUID,
        serverCharacterId: String,
        checkpointId: String,
        enqueuedAt: Date = Date(),
        attempts: Int = 0,
        payload: Data
    ) {
        self.id = id
        self.characterID = characterID
        self.serverCharacterId = serverCharacterId
        self.checkpointId = checkpointId
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.payload = payload
    }
}

final class MultiplayerLocalStore {
    let networkDirectory: URL
    let accountURL: URL
    let sessionURL: URL
    let checkpointQueueURL: URL
    let guildCacheURL: URL
    let realmCacheURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(dataDirectory: DataDirectory) throws {
        networkDirectory = dataDirectory.root.appendingPathComponent("network", isDirectory: true)
        accountURL = networkDirectory.appendingPathComponent("account.json")
        sessionURL = networkDirectory.appendingPathComponent("session.json")
        checkpointQueueURL = networkDirectory.appendingPathComponent("checkpoint-queue.jsonl")
        guildCacheURL = networkDirectory.appendingPathComponent("guild-cache.json")
        realmCacheURL = networkDirectory.appendingPathComponent("realm-cache.json")

        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: networkDirectory, withIntermediateDirectories: true)
    }

    func loadAccount() -> MultiplayerAccountProfile? {
        guard let data = try? Data(contentsOf: accountURL) else { return nil }
        return try? decoder.decode(MultiplayerAccountProfile.self, from: data)
    }

    func saveAccount(_ account: MultiplayerAccountProfile?) throws {
        if let account {
            let data = try encoder.encode(account)
            try data.write(to: accountURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: accountURL.path) {
            try FileManager.default.removeItem(at: accountURL)
        }
    }

    func loadSession() -> MultiplayerSession? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? decoder.decode(MultiplayerSession.self, from: data)
    }

    func saveSession(_ session: MultiplayerSession?) throws {
        if let session {
            let data = try encoder.encode(session)
            try data.write(to: sessionURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: sessionURL.path) {
            try FileManager.default.removeItem(at: sessionURL)
        }
    }

    func loadRealmCache() -> MultiplayerRealmCache? {
        guard let data = try? Data(contentsOf: realmCacheURL) else { return nil }
        return try? decoder.decode(MultiplayerRealmCache.self, from: data)
    }

    func saveRealmCache(_ cache: MultiplayerRealmCache?) throws {
        if let cache {
            let data = try encoder.encode(cache)
            try data.write(to: realmCacheURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: realmCacheURL.path) {
            try FileManager.default.removeItem(at: realmCacheURL)
        }
    }

    func loadGuildCache() -> MultiplayerGuildCache? {
        guard let data = try? Data(contentsOf: guildCacheURL) else { return nil }
        return try? decoder.decode(MultiplayerGuildCache.self, from: data)
    }

    func saveGuildCache(_ cache: MultiplayerGuildCache?) throws {
        if let cache {
            let data = try encoder.encode(cache)
            try data.write(to: guildCacheURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: guildCacheURL.path) {
            try FileManager.default.removeItem(at: guildCacheURL)
        }
    }

    func appendCheckpointQueueItem(_ item: MultiplayerCheckpointQueueItem) throws {
        let data = try encoder.encode(item)
        let line = data + Data([0x0A])
        if FileManager.default.fileExists(atPath: checkpointQueueURL.path) {
            let handle = try FileHandle(forWritingTo: checkpointQueueURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: checkpointQueueURL, options: .atomic)
        }
    }

    func loadCheckpointQueue() -> [MultiplayerCheckpointQueueItem] {
        guard let text = try? String(contentsOf: checkpointQueueURL, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(MultiplayerCheckpointQueueItem.self, from: data)
            }
    }
}
