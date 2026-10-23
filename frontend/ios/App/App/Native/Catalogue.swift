import Foundation

struct ExerciseInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var equipment: String
    var bodyPart: String
    var muscles: [String: Double]
}

struct EquipmentOption: Identifiable, Hashable {
    var id: String
    var label: String
}

enum Catalogue {
    static let muscleOrder = [
        "trapezius", "deltoids", "chest", "upper-back", "serratus",
        "biceps", "triceps", "forearm",
        "abs", "obliques", "lower-back",
        "gluteal", "quadriceps", "hamstring", "adductors", "hip-flexors",
        "calves", "tibialis",
    ]

    static let exercises: [ExerciseInfo] = load()
    static let byId: [String: ExerciseInfo] = {
        var index: [String: ExerciseInfo] = [:]
        for exercise in exercises { index[exercise.id] = exercise }
        return index
    }()

    static let equipment: [EquipmentOption] = {
        let ids = Set(exercises.map(\.equipment).filter { !$0.isEmpty })
        return ids.map { EquipmentOption(id: $0, label: equipmentName($0)) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }()

    static func search(_ query: String, owned: Set<String>?) -> [ExerciseInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return exercises.filter { exercise in
            if let owned {
                if owned.isEmpty || !owned.contains(exercise.equipment) { return false }
            }
            if trimmed.isEmpty { return true }
            return exercise.name.localizedStandardContains(trimmed)
                || equipmentName(exercise.equipment).localizedStandardContains(trimmed)
                || bodyPartName(exercise.bodyPart).localizedStandardContains(trimmed)
        }
    }

    static func muscleName(_ id: String) -> String {
        switch id {
        case "trapezius": return "斜方肌"
        case "deltoids": return "肩"
        case "chest": return "胸"
        case "upper-back": return "上背"
        case "serratus": return "前锯肌"
        case "biceps": return "二头"
        case "triceps": return "三头"
        case "forearm": return "前臂"
        case "abs": return "腹"
        case "obliques": return "腹外斜"
        case "lower-back": return "下背"
        case "gluteal": return "臀"
        case "quadriceps": return "股四"
        case "hamstring": return "腘绳"
        case "adductors": return "内收"
        case "hip-flexors": return "髋屈"
        case "calves": return "小腿"
        case "tibialis": return "胫骨前"
        default: return id
        }
    }

    static func equipmentName(_ id: String) -> String {
        switch id {
        case "assisted": return "辅助"
        case "band", "resistance band": return "弹力带"
        case "barbell": return "杠铃"
        case "body weight": return "自重"
        case "bosu ball": return "波速球"
        case "cable": return "绳索"
        case "dumbbell": return "哑铃"
        case "elliptical machine": return "椭圆机"
        case "ez barbell": return "EZ杠"
        case "hammer": return "锤"
        case "kettlebell": return "壶铃"
        case "landmine": return "地雷架"
        case "leverage machine": return "器械"
        case "macebell": return "锤铃"
        case "medicine ball": return "药球"
        case "olympic barbell": return "奥杠"
        case "roller": return "泡沫轴"
        case "rope": return "绳"
        case "sandbag": return "沙袋"
        case "skierg machine": return "滑雪机"
        case "sled machine": return "雪橇"
        case "smith machine": return "史密斯机"
        case "stability ball": return "稳定球"
        case "stationary bike": return "固定自行车"
        case "stepmill machine": return "台阶机"
        case "suspension trainer": return "悬挂带"
        case "tire": return "轮胎"
        case "trap bar": return "六角杠"
        case "upper body ergometer": return "上肢功率车"
        case "weight plate": return "杠铃片"
        case "weighted": return "负重"
        case "wheel roller": return "健腹轮"
        default: return id.isEmpty ? "其他" : id
        }
    }

    static func bodyPartName(_ id: String) -> String {
        switch id {
        case "chest": return "胸"
        case "back": return "背"
        case "shoulders": return "肩"
        case "upper arms": return "上臂"
        case "lower arms": return "前臂"
        case "waist": return "腰腹"
        case "upper legs": return "大腿"
        case "lower legs": return "小腿"
        case "cardio": return "有氧"
        case "neck": return "颈"
        default: return id
        }
    }

    static func muscleSummary(_ exercise: ExerciseInfo) -> String {
        exercise.muscles.sorted { $0.value > $1.value }
            .prefix(3)
            .map { muscleName($0.key) }
            .joined(separator: " · ")
    }

    private struct Record: Decodable {
        var id: String
        var name: String
        var equipment: String
        var bodyPart: String
        var muscles: [String: Double]
    }

    private static func load() -> [ExerciseInfo] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records.map {
            ExerciseInfo(id: $0.id, name: $0.name, equipment: $0.equipment, bodyPart: $0.bodyPart, muscles: $0.muscles)
        }
    }
}
