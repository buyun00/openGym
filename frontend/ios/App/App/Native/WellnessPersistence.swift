import Foundation

enum WellnessPersistence {
    static func read(from url: URL) throws -> WellnessState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(WellnessState.self, from: Data(contentsOf: url))
        guard value.version == 1, value.settings.isValid,
              value.water.allSatisfy({ (1...5000).contains($0.milliliters) }),
              Set(value.water.map(\.id)).count == value.water.count,
              Set(value.doses.map(\.id)).count == value.doses.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    static func write(_ value: WellnessState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
