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
        let comparisonInterval = DateInterval(start: analysis.previousPeriod.start, end: interval.end)
        var candidates: [TrainingRecommendation] = []

        for group in analysis.groups where analysis.historyAgeDays >= 28 &&
            group.target.category.accents.count > 1 && group.directSets >= 3 &&
            group.trainingDays >= 3 && group.exerciseIDs.count >= 2 {
            let category = group.target.category
            let accents = analysis.accents.filter { $0.target.category == category }
            let represented = accents.filter { $0.directSets > 0 || $0.indirectSets > 0 }
            guard represented.count == 1,
                  !shown.contains(where: { $0.id.hasPrefix("accent-\(category)-") ||
                                           $0.id == "distribution-\(category)" ||
                                           $0.id == "indirect-\(category)" }) else { continue }
            candidates.append(TrainingRecommendation(
                id: "review-accents-\(category)", category: .muscleAccents,
                title: "Посмотреть акценты: \(category.rawValue)",
                explanation: "В записях за период представлен один основной акцент. Можно посмотреть распределение прямой и косвенной работы без оценки достаточности нагрузки.",
                period: interval, observationCount: group.observationCount,
                metrics: [PersonalInsightMetric(name: "Акценты с записанной работой", value: Double(represented.count), unit: ""),
                          PersonalInsightMetric(name: "Прямые подходы", value: Double(group.directSets), unit: ""),
                          PersonalInsightMetric(name: "Косвенные подходы", value: Double(group.indirectSets), unit: "")],
                action: .muscleStructure(category), priority: 70))
        }

        for exercise in analysis.exercises where exercise.canInferTrend &&
            (exercise.trend == .improvement || exercise.trend == .stable) &&
            !exercise.isPersonalRecord {
            guard !shown.contains(where: { $0.id.contains(exercise.exerciseID.uuidString) }),
                  let latest = exercise.latest, let previous = exercise.previous else { continue }
            let unit: String
            switch exercise.metric {
            case .estimatedOneRepMax: unit = "кг e1RM"
            case .repetitions: unit = "повт."
            case .durationSeconds: unit = "сек."
            case .cardioDurationSeconds, .cardioDistanceKilometers: continue
            }
            candidates.append(TrainingRecommendation(
                id: "review-progress-\(exercise.id)", category: .exerciseProgress,
                title: "Посмотреть динамику: \(exercise.name)",
                explanation: exercise.trend == .stable
                    ? "Несколько сопоставимых выполнений дали одинаковый результат. Подробная история покажет его во времени."
                    : "В нескольких сопоставимых выполнениях результат менялся в одном направлении. Подробная история покажет динамику.",
                period: exercise.observationPeriod, observationCount: exercise.observationCount,
                metrics: [PersonalInsightMetric(name: "Последний результат", value: latest, unit: unit),
                          PersonalInsightMetric(name: "Предыдущий результат", value: previous, unit: unit)],
                action: .exerciseProgress(exercise.exerciseID), priority: 80))
        }

        if analysis.readiness == .detailed,
           !shown.contains(where: { $0.category == .muscleStructure }) {
            let total = analysis.groups.reduce(0) { $0 + $1.directSets }
            let previousTotal = analysis.groups.reduce(0) { $0 + $1.previousDirectSets }
            if total > 0 && previousTotal > 0 {
            for group in analysis.groups where group.canComparePeriods &&
                group.directSets > 0 && group.previousDirectSets > 0 {
                let currentShare = Double(group.directSets) / Double(total)
                let previousShare = Double(group.previousDirectSets) / Double(previousTotal)
                guard abs(currentShare - previousShare) >= 0.1 else { continue }
                candidates.append(TrainingRecommendation(
                    id: "review-distribution-\(group.target.category)", category: .trainingDistribution,
                    title: "Посмотреть распределение тренировок",
                    explanation: "Доля прямых подходов группы «\(group.target.category.rawValue)» изменилась относительно сопоставимого прошлого периода.",
                    period: comparisonInterval, observationCount: group.observationCount,
                    metrics: [PersonalInsightMetric(name: "Доля сейчас", value: currentShare * 100, unit: "%"),
                              PersonalInsightMetric(name: "Доля ранее", value: previousShare * 100, unit: "%"),
                              PersonalInsightMetric(name: "Прямые подходы сейчас", value: Double(group.directSets), unit: ""),
                              PersonalInsightMetric(name: "В прошлом периоде", value: Double(group.previousDirectSets), unit: "")],
                    action: .muscleStructure(group.target.category), priority: 60))
            }
            }
        }

        let regularity = analysis.regularity
        if regularity.canComparePeriods,
           let change = regularity.workoutChange, abs(change) >= 2,
           regularity.workoutCount > 0, regularity.previousWorkoutCount > 0,
           !shown.contains(where: { $0.category == .regularity }) {
            candidates.append(TrainingRecommendation(
                id: "review-regularity", category: .regularity,
                title: "Посмотреть регулярность",
                explanation: "Частота записанных тренировок отличается от прошлого сопоставимого периода. Это наблюдение, не оценка режима.",
                period: comparisonInterval, observationCount: regularity.observationCount,
                metrics: [PersonalInsightMetric(name: "Тренировки сейчас", value: Double(regularity.workoutCount), unit: ""),
                          PersonalInsightMetric(name: "В прошлом периоде", value: Double(regularity.previousWorkoutCount), unit: "")],
                action: nil, priority: 50))
        }

        var usedCategories = Set<String>()
        return Array(candidates.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
            .filter { usedCategories.insert(String(describing: $0.category)).inserted }
            .prefix(2))
    }
}
