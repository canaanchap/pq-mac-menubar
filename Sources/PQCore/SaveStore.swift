import Foundation

public final class SaveStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let saveURL: URL

    public init(dataDirectory: DataDirectory) {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        saveURL = dataDirectory.saves.appendingPathComponent("current.json")
    }

    public func load() -> GameState? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        return try? decoder.decode(GameState.self, from: data)
    }

    public func save(_ state: GameState) throws {
        let data = try encoder.encode(state)
        try data.write(to: saveURL, options: .atomic)
    }

    public var currentSaveURL: URL { saveURL }
}
