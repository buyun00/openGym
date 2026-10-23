import Foundation

struct WorkoutCatalogueRecord: Decodable {
    var name: String
    var englishName: String
    var mode: WorkoutMode
    var equipment: String
    var bodyPart: String
    var instructions: [String]
    var target: String
    var incline: Bool
    var clip: String?
    var still: String?

    func mediaURL(animated: Bool) -> URL? {
        guard let file = animated ? clip : still, !file.contains("/"), !file.contains("..") else { return nil }
        let subdirectory = "media/\(animated ? "clip" : "still")"
        return Bundle.main.url(forResource: file, withExtension: nil, subdirectory: subdirectory)
    }
}

enum WorkoutCatalogue {
    static let records: [String: WorkoutCatalogueRecord] = {
        guard let url = Bundle.main.url(forResource: "workout-catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: WorkoutCatalogueRecord].self, from: data) else { return [:] }
        return result
    }()
}

extension ExerciseInfo {
    var workoutMode: WorkoutMode { WorkoutCatalogue.records[id]?.mode ?? (bodyPart == "cardio" ? .cardio : .reps) }
}
