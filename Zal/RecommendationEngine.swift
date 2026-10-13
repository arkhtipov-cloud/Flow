import Foundation

enum RecommendationCategory {
    case muscleAccents
    case exerciseProgress
    case trainingDistribution
    case regularity
}

enum RecommendationAction {
    case muscleStructure(ExerciseCategory?)
    case exerciseProgress(UUID)
}

struct TrainingRecommendation: Identifiable {
    let id: String
    let category: RecommendationCategory
    let title: String
    let explanation: String
    let period: DateInterval
    let previousPeriod: DateInterval?
    let observationCount: Int
    let metrics: [PersonalInsightMetric]
    let action: RecommendationAction?
    let priority: Int
}

@MainActor enum RecommendationEngine {
    static func recommendations(analysis: MuscleAnalysisSnapshot,
                                insights: PersonalInsightsResult) -> [TrainingRecommendation] {
        guard analysis.readiness == .preliminary || analysis.readiness == .detailed else { return [] }
        let shown = insights.insights
        let interval = analysis.period
        var candidates: [TrainingRecommendation] = []

        for group in analysis.groups where analysis.historyAgeDays >= 28 &&
            group.target.category.accents.count > 1 && group.directSets >= 3 &&
            group.trainingDays >= 3 && group.exerciseIDs.count >= 2 {
            let category = group.target.category
            let accents = analysis.accents.filter { $0.target.category == category }
            let represented = accents.filter { $0.directSets > 0 || $0.indirectSets > 0 }
            guard represented.count == 1, represented[0].directSets == group.directSets,
                  !shown.contains(where: { $0.id.hasPrefix("accent-\(category)-") ||
                                           $0.id == "distribution-\(category)" ||
                                           $0.id == "indirect-\(category)" }) else { continue }
            let count = group.directSets
            let setForm: String
            if (11...14).contains(count % 100) {
                setForm = "прямых подходов"
            } else {
                switch count % 10 {
                case 1: setForm = "прямой подход"
                case 2...4: setForm = "прямых подхода"
                default: setForm = "прямых подходов"
                }
            }
            let accent = represented[0].target.accent?.trimmingCharacters(in: .whitespacesAndNewlines)
            let explanation = if let accent, !accent.isEmpty {
                "Акцент «\(accent)»: \(count) \(setForm) за период; косвенные учтены отдельно."
            } else {
                "За период записано \(count) \(setForm) группы; акцент не указан, косвенные учтены отдельно."
            }
            candidates.append(TrainingRecommendation(
                id: "review-accents-\(category)", category: .muscleAccents,
                title: "Посмотреть акценты: \(category.rawValue)",
                explanation: explanation,
                period: interval, previousPeriod: nil, observationCount: group.observationCount,
                metrics: [PersonalInsightMetric(name: "Акценты с записанной работой", value: Double(represented.count), unit: ""),
                          PersonalInsightMetric(name: "Прямые подходы", value: Double(group.directSets), unit: ""),
                          PersonalInsightMetric(name: "Косвенные подходы", value: Double(group.indirectSets), unit: "")],
                action: .muscleStructure(category), priority: 70))
        }

        for exercise in analysis.exercises where exercise.canInferTrend &&
            exercise.trend == .improvement &&
            !exercise.isPersonalRecord {
            guard !shown.contains(where: { $0.id.contains(exercise.exerciseID.uuidString) }),
                  let latest = exercise.latest, let previous = exercise.previous else { continue }
            let unit: String
            let resultName: String
            let increaseVerb: String
            switch exercise.metric {
            case .estimatedOneRepMax:
                unit = "кг"; resultName = "оценка силы"; increaseVerb = "выросла"
            case .repetitions:
                unit = "повт."; resultName = "число повторений"; increaseVerb = "выросло"
            case .durationSeconds:
                unit = "сек."; resultName = "длительность"; increaseVerb = "увеличилась"
            case .cardioDurationSeconds, .cardioDistanceKilometers: continue
            }
            candidates.append(TrainingRecommendation(
                id: "review-progress-\(exercise.id)", category: .exerciseProgress,
                title: "Посмотреть динамику: \(exercise.name)",
                explanation: "За пять последних сопоставимых выполнений \(resultName) в целом \(increaseVerb).",
                period: exercise.trendPeriod ?? exercise.observationPeriod, previousPeriod: nil,
                observationCount: exercise.recentValues.count,
                metrics: [PersonalInsightMetric(name: "Последний показатель", value: latest, unit: unit),
                          PersonalInsightMetric(name: "Предыдущий показатель", value: previous, unit: unit),
                          PersonalInsightMetric(name: "Всего сопоставимых выполнений", value: Double(exercise.observationCount), unit: "")],
                action: .exerciseProgress(exercise.exerciseID), priority: 80))
        }

        if analysis.readiness == .detailed {
            let total = analysis.groups.reduce(0) { $0 + $1.directSets }
            let previousTotal = analysis.groups.reduce(0) { $0 + $1.previousDirectSets }
            if total > 0 && previousTotal > 0 {
            for group in analysis.groups where group.canComparePeriods &&
                group.directSets > 0 && group.previousDirectSets > 0 &&
                !shown.contains(where: { $0.id == "distribution-\(group.target.category)" }) {
                let currentShare = Double(group.directSets) / Double(total)
                let previousShare = Double(group.previousDirectSets) / Double(previousTotal)
                guard abs(currentShare - previousShare) >= 0.1 else { continue }
                candidates.append(TrainingRecommendation(
                    id: "review-distribution-\(group.target.category)", category: .trainingDistribution,
                    title: "Посмотреть распределение тренировок",
                    explanation: "Доля прямых подходов группы «\(group.target.category.rawValue)» \(currentShare > previousShare ? "выросла" : "снизилась") относительно сопоставимого прошлого периода.",
                    period: interval, previousPeriod: analysis.previousPeriod,
                    observationCount: group.directSets + group.previousDirectSets,
                    metrics: [PersonalInsightMetric(name: "Доля прямых подходов — текущий период", value: currentShare * 100, unit: "%"),
                              PersonalInsightMetric(name: "Доля прямых подходов — предыдущий период", value: previousShare * 100, unit: "%"),
                              PersonalInsightMetric(name: "Прямые подходы — текущий период", value: Double(group.directSets), unit: ""),
                              PersonalInsightMetric(name: "Прямые подходы — предыдущий период", value: Double(group.previousDirectSets), unit: "")],
                    action: .muscleStructure(group.target.category), priority: 60))
            }
            }
        }

        let regularity = analysis.regularity
        if regularity.canComparePeriods,
           let change = regularity.workoutChange, abs(change) >= 2,
           regularity.workoutCount > 0, regularity.previousWorkoutCount > 0,
           !shown.contains(where: { $0.id == "training-frequency" }) {
            candidates.append(TrainingRecommendation(
                id: "review-regularity", category: .regularity,
                title: "Посмотреть регулярность",
                explanation: "В выбранном периоде \(regularity.workoutCount) тренировок, в прошлом сопоставимом — \(regularity.previousWorkoutCount).",
                period: interval, previousPeriod: analysis.previousPeriod,
                observationCount: regularity.workoutCount + regularity.previousWorkoutCount,
                metrics: [PersonalInsightMetric(name: "Тренировки — текущий период", value: Double(regularity.workoutCount), unit: ""),
                          PersonalInsightMetric(name: "Тренировки — предыдущий период", value: Double(regularity.previousWorkoutCount), unit: "")],
                action: nil, priority: 50))
        }

        var usedCategories = Set<String>()
        return Array(candidates.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
            .filter { usedCategories.insert(String(describing: $0.category)).inserted }
            .prefix(2))
    }
}
