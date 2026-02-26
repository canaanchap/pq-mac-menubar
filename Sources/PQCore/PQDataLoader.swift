import Foundation

public enum PQDataLoader {
    public static func load(from url: URL) throws -> PQDataBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(PQDataBundle.self, from: data)
    }
}
