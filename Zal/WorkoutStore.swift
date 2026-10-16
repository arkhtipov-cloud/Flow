import Foundation
import Combine
import UIKit

enum ExerciseTrackingType: String, CaseIterable, Codable, Identifiable {
    case weightReps
    case reps
    case duration
    case cardio

    var id: Self { self }
    var title: String {
        switch self {
        case .weightReps: "Вес и повторения"
        case .reps: "Повторения"
        case .duration: "Время"
        case .cardio: "Кардио — время и дистанция"
        }
    }
}

enum ExerciseCategory: String, CaseIterable, Codable, Identifiable {
    case chest = "Грудь"
    case back = "Спина"
    case legs = "Ноги"
    case shoulders = "Плечи"
    case biceps = "Бицепс"
    case triceps = "Трицепс"
    case forearms = "Предплечья"
    case abs = "Пресс"
    case cardio = "Кардио"

    var id: Self { self }

    var accents: [String] {
        switch self {
        case .chest: ["Верх груди", "Средняя часть груди", "Низ груди"]
        case .back: ["Широчайшие", "Средняя часть спины", "Трапеции"]
        case .legs: ["Квадрицепс", "Задняя поверхность бедра", "Ягодичные", "Икроножные"]
        case .shoulders: ["Передняя дельта", "Средняя дельта", "Задняя дельта"]
        case .biceps: ["Бицепс", "Брахиалис"]
        case .triceps: ["Трицепс"]
        case .forearms: ["Сгибатели предплечья", "Разгибатели предплечья", "Плечелучевая"]
        case .abs: ["Прямая мышца живота", "Кор"]
        case .cardio: []
        }
    }

    var illustrationID: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .legs: "figure.run"
        case .shoulders: "figure.boxing"
        case .biceps: "dumbbell"
        case .triceps: "figure.strengthtraining.traditional"
        case .forearms: "figure.strengthtraining.traditional"
        case .abs: "figure.core.training"
        case .cardio: "figure.run"
        }
    }
}

struct MuscleTarget: Codable, Hashable {
    let category: ExerciseCategory
    let accent: String?

    init(_ category: ExerciseCategory, _ accent: String? = nil) {
        self.category = category
        self.accent = accent
    }
}

struct MuscleMap: Codable, Hashable {
    let primaryGroup: ExerciseCategory?
    let primaryAccent: String?
    let secondaryMuscles: [MuscleTarget]
}

struct ExerciseDefinition: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: ExerciseCategory
    var isCustom: Bool = true
    var illustrationID: String = "figure.strengthtraining.traditional"
    var trackingType: ExerciseTrackingType = .weightReps
    var muscleAccent: String?
    var secondaryMuscles: [MuscleTarget] = []

    var searchAliases: [String] {
        guard !isCustom else { return [] }
        switch name {
        case "Бабочка": return ["Бабочка (сведение рук в тренажёре)", "Pec Deck", "Пек-дек"]
        case "Жим от груди в тренажёре": return ["Жим в грудном тренажёре"]
        case "Сгибание рук в тренажёре": return ["Сгибание рук в тренажёре на бицепс"]
        case "Жим на плечи в тренажёре": return ["Жим плечами в тренажёре"]
        case "Тяга горизонтального блока": return ["Горизонтальная тяга блока"]
        case "Разгибание рук на блоке": return ["Разгибание рук на верхнем блоке"]
        default: return []
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([name] + searchAliases).contains { $0.localizedStandardContains(query) }
    }

    private enum CodingKeys: String, CodingKey { case id, name, category, isCustom, illustrationID, trackingType, muscleAccent, secondaryMuscles }

    init(id: UUID = UUID(), name: String, category: ExerciseCategory, isCustom: Bool = true, illustrationID: String? = nil, trackingType: ExerciseTrackingType = .weightReps, muscleAccent: String? = nil, secondaryMuscles: [MuscleTarget] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.isCustom = isCustom
        self.illustrationID = illustrationID ?? (isCustom ? "figure.strengthtraining.traditional" : category.illustrationID)
        self.trackingType = trackingType
        self.muscleAccent = muscleAccent
        self.secondaryMuscles = secondaryMuscles
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        category = try values.decodeIfPresent(ExerciseCategory.self, forKey: .category) ?? .chest
        isCustom = try values.decodeIfPresent(Bool.self, forKey: .isCustom) ?? true
        illustrationID = try values.decodeIfPresent(String.self, forKey: .illustrationID) ?? (isCustom ? "figure.strengthtraining.traditional" : category.illustrationID)
        trackingType = try values.decodeIfPresent(ExerciseTrackingType.self, forKey: .trackingType) ?? .weightReps
        muscleAccent = try values.decodeIfPresent(String.self, forKey: .muscleAccent)
        secondaryMuscles = try values.decodeIfPresent([MuscleTarget].self, forKey: .secondaryMuscles) ?? []
    }

    static let builtIn: [ExerciseDefinition] = {
        let groups: [(ExerciseCategory, [String])] = [
            (.chest, ["Жим штанги лёжа", "Жим гантелей лёжа", "Жим гантелей на наклонной скамье", "Сведение рук в кроссовере", "Отжимания на брусьях"]),
            (.back, ["Подтягивания", "Подтягивания с весом", "Тяга штанги к поясу", "Тяга гантели одной рукой", "Тяга верхнего блока", "Тяга горизонтального блока"]),
            (.legs, ["Приседания со штангой", "Жим ногами", "Румынская тяга", "Разгибание ног", "Сгибание ног", "Подъём на носки"]),
            (.shoulders, ["Жим гантелей сидя", "Жим штанги стоя", "Подъём гантелей в стороны", "Разведение гантелей в наклоне"]),
            (.biceps, ["Подъём штанги на бицепс", "Подъём гантелей на бицепс", "Молотковые сгибания"]),
            (.triceps, ["Разгибание рук на блоке", "Французский жим", "Разгибание руки из-за головы"]),
            (.abs, ["Скручивания", "Подъём ног", "Подъём ног в висе", "Планка"])
        ]
        let illustrations = [
            "Жим гантелей лёжа": "chest_dumbbell_bench",
            "Жим гантелей на наклонной скамье": "chest_incline_dumbbell",
            "Жим штанги лёжа": "chest_barbell_bench",
            "Отжимания на брусьях": "chest_dips",
            "Сведение рук в кроссовере": "chest_cable_crossover",
            "Подтягивания": "back_pullup",
            "Подтягивания с весом": "back_weighted_pullup",
            "Тяга верхнего блока": "back_lat_pulldown",
            "Тяга гантели одной рукой": "back_one_arm_dumbbell_row",
            "Тяга горизонтального блока": "back_seated_cable_row",
            "Тяга штанги к поясу": "back_barbell_row",
            "Шраги с гантелями": "back_dumbbell_shrugs",
            "Шраги со штангой": "back_barbell_shrugs",
            "Жим ногами": "legs_leg_press",
            "Подъём на носки": "legs_calf_raise",
            "Приседания со штангой": "legs_barbell_squat",
            "Разгибание ног": "legs_leg_extension",
            "Румынская тяга": "legs_romanian_deadlift",
            "Сгибание ног": "legs_leg_curl",
            "Жим гантелей сидя": "shoulders_seated_dumbbell_press",
            "Жим штанги стоя": "shoulders_standing_barbell_press",
            "Подъём гантелей в стороны": "shoulders_lateral_raise",
            "Подъём гантелей перед собой": "shoulders_front_raise",
            "Тяга штанги к подбородку": "shoulders_upright_row",
            "Разведение гантелей в наклоне": "shoulders_bent_over_raise",
            "Молотковые сгибания": "biceps_hammer_curl",
            "Подъём гантелей на бицепс": "biceps_dumbbell_curl",
            "Подъём штанги на бицепс": "biceps_barbell_curl",
            "Разгибание рук на блоке": "triceps_cable_pushdown",
            "Разгибание руки из-за головы": "triceps_overhead_extension",
            "Французский жим": "triceps_french_press",
            "Планка": "abs_plank",
            "Подъём ног": "abs_leg_raise",
            "Подъём ног в висе": "abs_hanging_leg_raise",
            "Скручивания": "abs_crunch",
            "Сгибание запястий со штангой": "forearms_wrist_curl_barbell",
            "Разгибание запястий со штангой": "forearms_wrist_extension_barbell",
            "Обратные сгибания со штангой": "forearms_reverse_barbell_curl",
            "Обратные сгибания рук в кроссовере": "forearms_reverse_cable_curl",
            "Бег": "cardio_run",
            "Ходьба": "cardio_walk",
            "Велотренажёр": "cardio_stationary_bike",
            "Эллипс": "cardio_elliptical",
            "Гребной тренажёр": "cardio_rowing_machine",
            "Степпер": "cardio_stepper"
        ]
        let repsExercises: Set<String> = ["Подтягивания", "Отжимания на брусьях", "Скручивания", "Подъём ног", "Подъём ног в висе"]
        let accents: [String: String] = [
            "Жим штанги лёжа": "Средняя часть груди", "Жим гантелей лёжа": "Средняя часть груди",
            "Жим гантелей на наклонной скамье": "Верх груди", "Сведение рук в кроссовере": "Средняя часть груди",
            "Отжимания на брусьях": "Низ груди",
            "Подтягивания": "Широчайшие", "Подтягивания с весом": "Широчайшие",
            "Тяга верхнего блока": "Широчайшие", "Тяга гантели одной рукой": "Широчайшие",
            "Тяга горизонтального блока": "Средняя часть спины", "Тяга штанги к поясу": "Средняя часть спины",
            "Шраги с гантелями": "Трапеции", "Шраги со штангой": "Трапеции",
            "Приседания со штангой": "Квадрицепс", "Жим ногами": "Квадрицепс", "Разгибание ног": "Квадрицепс",
            "Румынская тяга": "Задняя поверхность бедра", "Сгибание ног": "Задняя поверхность бедра",
            "Подъём на носки": "Икроножные",
            "Жим гантелей сидя": "Передняя дельта", "Жим штанги стоя": "Передняя дельта",
            "Подъём гантелей перед собой": "Передняя дельта", "Подъём гантелей в стороны": "Средняя дельта",
            "Тяга штанги к подбородку": "Средняя дельта", "Разведение гантелей в наклоне": "Задняя дельта",
            "Подъём штанги на бицепс": "Бицепс", "Подъём гантелей на бицепс": "Бицепс",
            "Молотковые сгибания": "Брахиалис",
            "Разгибание рук на блоке": "Трицепс", "Французский жим": "Трицепс",
            "Разгибание руки из-за головы": "Трицепс",
            "Сгибание запястий со штангой": "Сгибатели предплечья",
            "Разгибание запястий со штангой": "Разгибатели предплечья",
            "Обратные сгибания со штангой": "Плечелучевая",
            "Обратные сгибания рук в кроссовере": "Плечелучевая",
            "Скручивания": "Прямая мышца живота", "Подъём ног": "Прямая мышца живота",
            "Подъём ног в висе": "Прямая мышца живота", "Планка": "Кор"
        ]
        let secondaries: [String: [MuscleTarget]] = [
            "Жим штанги лёжа": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Передняя дельта")],
            "Жим гантелей лёжа": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Передняя дельта")],
            "Жим гантелей на наклонной скамье": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Передняя дельта")],
            "Отжимания на брусьях": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Передняя дельта")],
            "Подтягивания": [MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Подтягивания с весом": [MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Тяга верхнего блока": [MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Тяга гантели одной рукой": [MuscleTarget(.back, "Средняя часть спины"), MuscleTarget(.shoulders, "Задняя дельта"), MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Тяга горизонтального блока": [MuscleTarget(.back, "Широчайшие"), MuscleTarget(.shoulders, "Задняя дельта"), MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Тяга штанги к поясу": [MuscleTarget(.back, "Широчайшие"), MuscleTarget(.shoulders, "Задняя дельта"), MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")],
            "Приседания со штангой": [MuscleTarget(.legs, "Ягодичные")],
            "Жим ногами": [MuscleTarget(.legs, "Ягодичные")],
            "Румынская тяга": [MuscleTarget(.legs, "Ягодичные")],
            "Жим гантелей сидя": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Средняя дельта")],
            "Жим штанги стоя": [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Средняя дельта")],
            "Тяга штанги к подбородку": [MuscleTarget(.back, "Трапеции")],
            "Разведение гантелей в наклоне": [MuscleTarget(.back, "Средняя часть спины")],
            "Подъём штанги на бицепс": [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.forearms, "Плечелучевая")],
            "Подъём гантелей на бицепс": [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.forearms, "Плечелучевая")],
            "Молотковые сгибания": [MuscleTarget(.forearms, "Плечелучевая")],
            "Обратные сгибания со штангой": [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.biceps, "Бицепс")],
            "Обратные сгибания рук в кроссовере": [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.biceps, "Бицепс")]
        ]
        let original: [ExerciseDefinition] = groups.flatMap { category, names in names.map { (category, $0) } }.enumerated().compactMap { index, item -> ExerciseDefinition? in
            guard let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 1)) else { return nil }
            let trackingType: ExerciseTrackingType = item.1 == "Планка" ? .duration : repsExercises.contains(item.1) ? .reps : .weightReps
            return ExerciseDefinition(id: id, name: item.1, category: item.0, isCustom: false, illustrationID: illustrations[item.1], trackingType: trackingType, muscleAccent: accents[item.1], secondaryMuscles: secondaries[item.1] ?? [])
        }
        guard let frontRaiseID = UUID(uuidString: "00000000-0000-4000-8000-000000000020"),
              let uprightRowID = UUID(uuidString: "00000000-0000-4000-8000-000000000029") else { return original }
        let cardioNames = ["Бег", "Ходьба", "Велотренажёр", "Эллипс", "Гребной тренажёр", "Степпер"]
        let cardioExercises = cardioNames.enumerated().compactMap { index, name -> ExerciseDefinition? in
            guard let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 0x21)) else { return nil }
            return ExerciseDefinition(id: id, name: name, category: .cardio, isCustom: false, illustrationID: illustrations[name], trackingType: .cardio)
        }
        let shrugs = ["Шраги с гантелями", "Шраги со штангой"].enumerated().compactMap { index, name -> ExerciseDefinition? in
            guard let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 0x27)) else { return nil }
            return ExerciseDefinition(id: id, name: name, category: .back, isCustom: false, illustrationID: illustrations[name], trackingType: .weightReps, muscleAccent: accents[name], secondaryMuscles: secondaries[name] ?? [])
        }
        let forearmNames = ["Сгибание запястий со штангой", "Разгибание запястий со штангой", "Обратные сгибания со штангой"]
        let forearmExercises = forearmNames.enumerated().compactMap { index, name -> ExerciseDefinition? in
            guard let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 0x2A)) else { return nil }
            return ExerciseDefinition(id: id, name: name, category: .forearms, isCustom: false, illustrationID: illustrations[name], trackingType: .weightReps, muscleAccent: accents[name], secondaryMuscles: secondaries[name] ?? [])
        }
        guard let cableReverseCurlID = UUID(uuidString: "00000000-0000-4000-8000-00000000002D"),
              let pecDeckID = UUID(uuidString: "00000000-0000-4000-8000-00000000002E"),
              let chestPressID = UUID(uuidString: "00000000-0000-4000-8000-00000000002F"),
              let pulloverID = UUID(uuidString: "00000000-0000-4000-8000-000000000030"),
              let bicepsMachineID = UUID(uuidString: "00000000-0000-4000-8000-000000000031"),
              let shoulderPressID = UUID(uuidString: "00000000-0000-4000-8000-000000000032") else { return original }
        let cableReverseCurl = ExerciseDefinition(id: cableReverseCurlID, name: "Обратные сгибания рук в кроссовере", category: .forearms, isCustom: false, illustrationID: illustrations["Обратные сгибания рук в кроссовере"], trackingType: .weightReps, muscleAccent: accents["Обратные сгибания рук в кроссовере"], secondaryMuscles: secondaries["Обратные сгибания рук в кроссовере"] ?? [])
        let pecDeck = ExerciseDefinition(id: pecDeckID, name: "Бабочка", category: .chest,
                                         isCustom: false, trackingType: .weightReps, muscleAccent: "Средняя часть груди")
        let machines = [
            ExerciseDefinition(id: chestPressID, name: "Жим от груди в тренажёре", category: .chest, isCustom: false,
                               trackingType: .weightReps, muscleAccent: "Средняя часть груди",
                               secondaryMuscles: secondaries["Жим штанги лёжа"] ?? []),
            // Elbow-pad pullover: isolated shoulder extension, without elbow-flexion targets.
            ExerciseDefinition(id: pulloverID, name: "Пуловер в тренажёре", category: .back, isCustom: false,
                               trackingType: .weightReps, muscleAccent: "Широчайшие"),
            ExerciseDefinition(id: bicepsMachineID, name: "Сгибание рук в тренажёре", category: .biceps, isCustom: false,
                               trackingType: .weightReps, muscleAccent: "Бицепс",
                               secondaryMuscles: secondaries["Подъём штанги на бицепс"] ?? []),
            ExerciseDefinition(id: shoulderPressID, name: "Жим на плечи в тренажёре", category: .shoulders, isCustom: false,
                               trackingType: .weightReps, muscleAccent: "Передняя дельта",
                               secondaryMuscles: secondaries["Жим гантелей сидя"] ?? [])
        ]
        return original + [ExerciseDefinition(id: frontRaiseID, name: "Подъём гантелей перед собой", category: .shoulders, isCustom: false, illustrationID: illustrations["Подъём гантелей перед собой"], trackingType: .weightReps, muscleAccent: accents["Подъём гантелей перед собой"])] + cardioExercises + shrugs + [ExerciseDefinition(id: uprightRowID, name: "Тяга штанги к подбородку", category: .shoulders, isCustom: false, illustrationID: illustrations["Тяга штанги к подбородку"], trackingType: .weightReps, muscleAccent: accents["Тяга штанги к подбородку"], secondaryMuscles: secondaries["Тяга штанги к подбородку"] ?? [])] + forearmExercises + [cableReverseCurl, pecDeck] + machines
    }()
}

struct SetEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double = 0
    var repetitions: Int = 0
    var durationSeconds: Int = 0
    var distanceKilometers: Double?

    private enum CodingKeys: String, CodingKey { case id, weight, repetitions, durationSeconds, distanceKilometers }

    init(id: UUID = UUID(), weight: Double = 0, repetitions: Int = 0, durationSeconds: Int = 0, distanceKilometers: Double? = nil) {
        self.id = id
        self.weight = weight
        self.repetitions = repetitions
        self.durationSeconds = durationSeconds
        self.distanceKilometers = distanceKilometers
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        weight = try values.decodeIfPresent(Double.self, forKey: .weight) ?? 0
        repetitions = try values.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        distanceKilometers = try values.decodeIfPresent(Double.self, forKey: .distanceKilometers)
    }
}

extension SetEntry {
    func hasRecordedResult(for type: ExerciseTrackingType) -> Bool {
        switch type {
        case .weightReps: weight.isFinite && weight > 0 && repetitions > 0
        case .reps: repetitions > 0
        case .duration, .cardio: durationSeconds > 0
        }
    }
}

enum WorkoutSetClassifier {
    static func workingSets(_ sets: [SetEntry], type: ExerciseTrackingType) -> [SetEntry] {
        guard type == .weightReps else { return sets }
        let recorded = sets.enumerated().filter { $0.element.hasRecordedResult(for: type) }
        guard let maximum = recorded.map({ $0.element.weight }).max(),
              let firstHeavy = recorded.firstIndex(where: { $0.element.weight == maximum }),
              firstHeavy >= 2 else { return sets }
        let preparation = Array(recorded[..<firstHeavy])
        let heavy = recorded[firstHeavy...].prefix { $0.element.weight == maximum }
        guard heavy.count >= 2,
              let minReps = heavy.map({ $0.element.repetitions }).min(),
              let maxReps = heavy.map({ $0.element.repetitions }).max(),
              (1...12).contains(maxReps),
              maxReps - minReps <= 2,
              Set(preparation.map { $0.element.weight }).count >= 2,
              zip(preparation, preparation.dropFirst()).allSatisfy({ $0.element.weight <= $1.element.weight }) else { return sets }

        // Only a clearly lighter ascending prefix is inferred as preparation.
        // A near-working ramp, an isolated top set and all later back-off sets stay eligible.
        let heavyScore = maximum * (1 + Double(minReps) / 30)
        let warmupIndices = Set(preparation.filter { item in
            let entry = item.element
            let score = entry.weight * (1 + Double(entry.repetitions) / 30)
            return entry.weight <= maximum * 0.75 && (maxReps...12).contains(entry.repetitions) &&
                score.isFinite && heavyScore.isFinite && score <= heavyScore * 0.85
        }.map(\.offset))
        return sets.enumerated().filter { !warmupIndices.contains($0.offset) }.map(\.element)
    }
}

struct WorkoutExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: UUID
    var name: String
    var sets: [SetEntry] = [SetEntry()]
    var trackingType: ExerciseTrackingType = .weightReps
    var muscleMapSnapshot: MuscleMap?

    var analysisSets: [SetEntry] { WorkoutSetClassifier.workingSets(sets, type: trackingType) }

    private enum CodingKeys: String, CodingKey { case id, exerciseID, name, sets, trackingType, muscleMapSnapshot }

    init(id: UUID = UUID(), exerciseID: UUID, name: String, sets: [SetEntry] = [SetEntry()], trackingType: ExerciseTrackingType = .weightReps, muscleMapSnapshot: MuscleMap? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.trackingType = trackingType
        self.muscleMapSnapshot = muscleMapSnapshot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        exerciseID = try values.decode(UUID.self, forKey: .exerciseID)
        name = try values.decode(String.self, forKey: .name)
        sets = try values.decodeIfPresent([SetEntry].self, forKey: .sets) ?? []
        trackingType = try values.decodeIfPresent(ExerciseTrackingType.self, forKey: .trackingType) ?? .weightReps
        muscleMapSnapshot = try values.decodeIfPresent(MuscleMap.self, forKey: .muscleMapSnapshot)
    }
}

struct WorkoutRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date = Date()
    var exercises: [WorkoutExercise] = []
    var note: String? = nil
    var isTemplate = false
    var startedAt: Date?
    var finishedAt: Date?
    var splitTemplateID: UUID?
    var splitTemplateName: String?
    var splitCompletionRecorded: Bool?

    var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }

    mutating func moveExercise(_ exerciseID: UUID, to targetID: UUID) {
        guard exerciseID != targetID,
              let source = exercises.firstIndex(where: { $0.id == exerciseID }),
              let target = exercises.firstIndex(where: { $0.id == targetID }) else { return }
        let exercise = exercises.remove(at: source)
        exercises.insert(exercise, at: target)
    }
}

struct SplitTemplateExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: UUID
    var name: String
    var trackingType: ExerciseTrackingType
}

struct SplitWorkoutTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var exercises: [SplitTemplateExercise] = []
}

struct SplitPlan: Codable {
    var isEnabled = false
    var templates: [SplitWorkoutTemplate] = []
    var nextTemplateID: UUID?
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var records: [WorkoutRecord] = []
    @Published private(set) var exercises: [ExerciseDefinition] = ExerciseDefinition.builtIn
    @Published private(set) var splitPlan = SplitPlan()
    @Published var weeklyGoal = 4 {
        didSet { save() }
    }
    @Published private(set) var saveError: String?

    private struct SavedData: Codable {
        var records: [WorkoutRecord]
        var exercises: [ExerciseDefinition]
        var weeklyGoal: Int
        var splitPlan: SplitPlan?
    }

    private let fileURL: URL
    private let isEphemeral: Bool

    init(fileURL: URL? = nil, isEphemeral: Bool = false) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storageDirectory = isEphemeral
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ZalDemo", isDirectory: true)
            : support.appendingPathComponent("Zal", isDirectory: true)
        self.fileURL = fileURL ?? storageDirectory.appendingPathComponent("workouts.json")
        self.isEphemeral = isEphemeral
        if !isEphemeral { load() }
    }

    var workouts: [WorkoutRecord] {
        records.filter { !$0.isTemplate && !$0.exercises.isEmpty && ($0.splitTemplateID == nil || $0.splitCompletionRecorded == true) }.sorted { $0.date > $1.date }
    }

    var nextSplitTemplate: SplitWorkoutTemplate? {
        guard splitPlan.isEnabled, !splitPlan.templates.isEmpty else { return nil }
        return splitPlan.templates.first { $0.id == splitPlan.nextTemplateID } ?? splitPlan.templates.first
    }

    func setSplitEnabled(_ enabled: Bool) {
        splitPlan.isEnabled = enabled
        if splitPlan.nextTemplateID == nil { splitPlan.nextTemplateID = splitPlan.templates.first?.id }
        save()
    }

    func upsertSplitTemplate(_ template: SplitWorkoutTemplate) {
        if let index = splitPlan.templates.firstIndex(where: { $0.id == template.id }) {
            splitPlan.templates[index] = template
        } else {
            splitPlan.templates.append(template)
            if splitPlan.nextTemplateID == nil { splitPlan.nextTemplateID = template.id }
        }
        save()
    }

    func deleteSplitTemplates(at offsets: IndexSet) {
        let oldTemplates = splitPlan.templates
        let removedNext = offsets.contains { oldTemplates[$0].id == splitPlan.nextTemplateID }
        for index in offsets.sorted(by: >) { splitPlan.templates.remove(at: index) }
        if removedNext { splitPlan.nextTemplateID = splitPlan.templates.first?.id }
        save()
    }

    func moveSplitTemplates(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { splitPlan.templates[$0] }
        for index in source.sorted(by: >) { splitPlan.templates.remove(at: index) }
        let target = destination - source.filter { $0 < destination }.count
        splitPlan.templates.insert(contentsOf: moving, at: target)
        save()
    }

    func skipNextSplitTemplate(on date: Date) {
        guard let nextSplitTemplate else { return }
        records.removeAll {
            $0.splitTemplateID == nextSplitTemplate.id &&
            $0.splitCompletionRecorded != true &&
            !hasRecordedResult($0) &&
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        advanceSplit(after: nextSplitTemplate.id)
        save()
    }

    func prepareNextSplitWorkout(on date: Date) -> WorkoutRecord? {
        guard let template = nextSplitTemplate else { return nil }
        let calendar = Calendar.current
        if let existing = records.first(where: { !$0.isTemplate && $0.splitTemplateID == template.id && $0.splitCompletionRecorded != true && calendar.isDate($0.date, inSameDayAs: date) }) {
            return existing
        }
        if let unfinished = records.filter({ !$0.isTemplate && $0.splitTemplateID == template.id && $0.splitCompletionRecorded != true })
            .max(by: { $0.date < $1.date }) {
            return unfinished
        }
        let items = template.exercises.map {
            WorkoutExercise(exerciseID: $0.exerciseID, name: $0.name, sets: $0.trackingType == .cardio ? [SetEntry()] : [], trackingType: $0.trackingType)
        }
        var record = WorkoutRecord(title: template.name, date: date, exercises: items)
        record.splitTemplateID = template.id
        record.splitTemplateName = template.name
        upsert(record)
        return record
    }

    func previousSplitWorkout(for record: WorkoutRecord) -> WorkoutRecord? {
        guard let templateID = record.splitTemplateID else { return nil }
        return records.filter { $0.id != record.id && $0.splitTemplateID == templateID && $0.splitCompletionRecorded == true && $0.date <= record.date }
            .max { $0.date < $1.date }
    }

    private func advanceSplit(after templateID: UUID) {
        guard let index = splitPlan.templates.firstIndex(where: { $0.id == templateID }), !splitPlan.templates.isEmpty else { return }
        splitPlan.nextTemplateID = splitPlan.templates[(index + 1) % splitPlan.templates.count].id
    }

    private func hasRecordedResult(_ record: WorkoutRecord) -> Bool {
        record.exercises.contains { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        }
    }

    func hasRecordedResult(_ recordID: UUID) -> Bool {
        guard let record = records.first(where: { $0.id == recordID }) else { return false }
        return hasRecordedResult(record)
    }

    func completeSplitWorkout(_ recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              let templateID = records[index].splitTemplateID,
              records[index].splitCompletionRecorded != true,
              hasRecordedResult(records[index]) else { return }
        records[index].splitCompletionRecorded = true
        if splitPlan.nextTemplateID == templateID {
            advanceSplit(after: templateID)
        }
        save()
    }

    var templates: [WorkoutRecord] {
        records.filter(\.isTemplate).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var thisWeekCount: Int {
        guard let interval = Self.statisticsCalendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return workouts.filter { interval.contains($0.date) && hasRecordedResult($0) }.count
    }

    var streakWeeks: Int {
        let calendar = Self.statisticsCalendar
        let activeWeeks = Set(workouts.filter { hasRecordedResult($0) }.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start
        })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        if !activeWeeks.contains(week) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { return 0 }
            week = previous
        }
        var count = 0
        while activeWeeks.contains(week) {
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    var thisWeekActivity: [Int] {
        let calendar = Self.statisticsCalendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return Array(repeating: 0, count: 7) }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return 0 }
            return workouts.filter { calendar.isDate($0.date, inSameDayAs: day) && hasRecordedResult($0) }.count
        }
    }

    func upsert(_ record: WorkoutRecord) {
        var record = record
        if record.splitTemplateID != nil {
            record.splitCompletionRecorded = records.first(where: { $0.id == record.id })?.splitCompletionRecorded
        }
        let previous = records.first(where: { $0.id == record.id })
        for index in record.exercises.indices where record.exercises[index].muscleMapSnapshot == nil {
            let item = record.exercises[index]
            record.exercises[index].muscleMapSnapshot = previous?.exercises.first(where: { $0.id == item.id })?.muscleMapSnapshot
                ?? muscleMap(for: item.exerciseID)
        }
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        save()
    }

    func moveExercise(_ exerciseID: UUID, to targetID: UUID, in workoutID: UUID) {
        guard var workout = records.first(where: { $0.id == workoutID }) else { return }
        let previousOrder = workout.exercises.map(\.id)
        workout.moveExercise(exerciseID, to: targetID)
        guard workout.exercises.map(\.id) != previousOrder else { return }
        upsert(workout)
    }

    func delete(_ record: WorkoutRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func muscleMap(for exerciseID: UUID) -> MuscleMap? {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return nil }
        guard exercise.category != .cardio && exercise.trackingType != .cardio else {
            return MuscleMap(primaryGroup: nil, primaryAccent: nil, secondaryMuscles: [])
        }
        let accent = exercise.category.accents.contains(exercise.muscleAccent ?? "")
            ? exercise.muscleAccent
            : (exercise.category.accents.count == 1 ? exercise.category.accents.first : nil)
        return MuscleMap(primaryGroup: exercise.category, primaryAccent: accent,
                         secondaryMuscles: exercise.secondaryMuscles)
    }

    func addExercise(named name: String, category: ExerciseCategory, trackingType: ExerciseTrackingType = .weightReps, muscleAccent: String? = nil, secondaryMuscles: [MuscleTarget] = [], imageData: Data? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !exercises.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        var definition = ExerciseDefinition(name: trimmed, category: category, trackingType: trackingType,
                                            muscleAccent: category.accents.contains(muscleAccent ?? "") ? muscleAccent : category.accents.first,
                                            secondaryMuscles: validSecondaryMuscles(secondaryMuscles, category: category, accent: muscleAccent, trackingType: trackingType))
        if let imageData, let filename = saveIllustration(imageData, for: definition.id) {
            definition.illustrationID = filename
        }
        exercises.append(definition)
        save()
    }

    func renameExercise(_ exercise: ExerciseDefinition, to name: String, category: ExerciseCategory? = nil, trackingType: ExerciseTrackingType? = nil, muscleAccent: String? = nil, secondaryMuscles: [MuscleTarget] = [], imageData: Data? = nil, removeImage: Bool = false) {
        guard exercise.isCustom else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !exercises.contains(where: { $0.id != exercise.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }),
              let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[index].name = trimmed
        if let category { exercises[index].category = category }
        if let trackingType { exercises[index].trackingType = trackingType }
        let currentCategory = exercises[index].category
        exercises[index].muscleAccent = currentCategory.accents.contains(muscleAccent ?? "") ? muscleAccent : currentCategory.accents.first
        exercises[index].secondaryMuscles = validSecondaryMuscles(secondaryMuscles, category: currentCategory, accent: exercises[index].muscleAccent, trackingType: exercises[index].trackingType)
        if removeImage { exercises[index].illustrationID = "figure.strengthtraining.traditional" }
        if let imageData, let filename = saveIllustration(imageData, for: exercise.id) {
            exercises[index].illustrationID = filename
        }
        for recordIndex in records.indices {
            for itemIndex in records[recordIndex].exercises.indices where records[recordIndex].exercises[itemIndex].exerciseID == exercise.id {
                records[recordIndex].exercises[itemIndex].name = trimmed
            }
        }
        save()
    }

    private func validSecondaryMuscles(_ targets: [MuscleTarget], category: ExerciseCategory, accent: String?, trackingType: ExerciseTrackingType) -> [MuscleTarget] {
        guard category != .cardio && trackingType != .cardio else { return [] }
        var seen = Set<MuscleTarget>()
        return targets.filter { target in
            guard target.category != .cardio,
                  target.category.accents.contains(target.accent ?? ""),
                  !(target.category == category && target.accent == accent) else { return false }
            return seen.insert(target).inserted
        }
    }

    func customIllustration(for exercise: ExerciseDefinition) -> UIImage? {
        guard exercise.isCustom, exercise.illustrationID == "custom_\(exercise.id.uuidString).png" else { return nil }
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("ExerciseImages", isDirectory: true)
            .appendingPathComponent(exercise.illustrationID)
        return UIImage(contentsOfFile: url.path)
    }

    private func saveIllustration(_ data: Data, for id: UUID) -> String? {
        guard let png = UIImage(data: data)?.pngData() else { return nil }
        let filename = "custom_\(id.uuidString).png"
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("ExerciseImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            saveError = "Не удалось сохранить иллюстрацию: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteExercise(_ exercise: ExerciseDefinition) {
        guard exercise.isCustom else { return }
        exercises.removeAll { $0.id == exercise.id }
        // Existing workout entries keep their names and results.
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try JSONDecoder().decode(SavedData.self, from: data)
            records = saved.records
            splitPlan = saved.splitPlan ?? SplitPlan()
            let legacy = saved.exercises.map { exercise -> ExerciseDefinition in
                guard let standard = ExerciseDefinition.builtIn.first(where: { $0.id == exercise.id || $0.name == exercise.name }) else { return exercise }
                return ExerciseDefinition(id: exercise.id, name: standard.name, category: standard.category, isCustom: false, illustrationID: standard.illustrationID, trackingType: standard.trackingType, muscleAccent: standard.muscleAccent, secondaryMuscles: standard.secondaryMuscles)
            }
            exercises = ExerciseDefinition.builtIn.filter { standard in !legacy.contains(where: { $0.name == standard.name }) } + legacy
            for recordIndex in records.indices {
                for itemIndex in records[recordIndex].exercises.indices where records[recordIndex].exercises[itemIndex].muscleMapSnapshot == nil {
                    let id = records[recordIndex].exercises[itemIndex].exerciseID
                    records[recordIndex].exercises[itemIndex].muscleMapSnapshot = muscleMap(for: id)
                }
            }
            weeklyGoal = max(1, min(7, saved.weeklyGoal))
        } catch CocoaError.fileReadNoSuchFile {
            // A new installation has no file yet.
        } catch {
            saveError = "Не удалось загрузить сохранённые данные: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard !isEphemeral else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let savedExercises = exercises.filter { exercise in
                exercise.isCustom || !ExerciseDefinition.builtIn.contains(where: { $0.id == exercise.id })
            }
            let data = try JSONEncoder().encode(SavedData(records: records, exercises: savedExercises, weeklyGoal: weeklyGoal, splitPlan: splitPlan))
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }
}
