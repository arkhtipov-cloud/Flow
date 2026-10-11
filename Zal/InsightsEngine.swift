import Foundation

enum PersonalInsightCategory { case muscleStructure, progress, regularity, achievement }
enum PersonalInsightConfidence { case preliminary, supported, strong }

struct PersonalInsightMetric {
    let name: String
    let value: Double
    let unit: String
}

// A separate, deterministic result for future Insights UI; the current snapshot remains unchanged.
@MainActor extension InsightsEngine {
    static func personalInsights(store: WorkoutStore, period: StatsPeriod, relativeTo date: Date = .now) -> PersonalInsightsResult {
        personalInsights(from: MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: date))
    }

    static func personalInsights(from analysis: MuscleAnalysisSnapshot) -> PersonalInsightsResult {
        guard analysis.readiness == .preliminary || analysis.readiness == .detailed else {
            return PersonalInsightsResult(readiness: analysis.readiness,
                                          observationCount: analysis.observationCount, insights: [])
        }
        let interval = analysis.period
        let comparisonInterval = DateInterval(start: analysis.previousPeriod.start, end: interval.end)
        var candidates: [PersonalInsight] = []
        func metric(_ name: String, _ value: Double, _ unit: String = "") -> PersonalInsightMetric {
            PersonalInsightMetric(name: name, value: value, unit: unit)
        }
        func confidence(_ count: Int, comparable: Bool = false) -> PersonalInsightConfidence {
            comparable && count >= 6 ? .strong : count >= 3 ? .supported : .preliminary
        }

        for item in analysis.exercises where item.canCompare {
            guard let latest = item.latest, let previous = item.previous else { continue }
            let subject = "exercise-\(item.id)"
            let unit: String
            switch item.metric {
            case .estimatedOneRepMax: unit = "кг e1RM"
            case .repetitions: unit = "повт."
            case .durationSeconds, .cardioDurationSeconds: unit = "сек."
            case .cardioDistanceKilometers: unit = "км"
            }
            let evidence = [metric("Последний результат", latest, unit),
                            metric("Предыдущий результат", previous, unit),
                            metric("Сопоставимые выполнения", Double(item.observationCount))]
            // Cardio time/distance is descriptive, not a universal measure of performance.
            let isCardio = item.metric == .cardioDurationSeconds || item.metric == .cardioDistanceKilometers
            if item.isPersonalRecord && !isCardio && analysis.historyAgeDays >= 7 {
                candidates.append(PersonalInsight(id: "pr-\(subject)", category: .achievement,
                    title: "Личный рекорд: \(item.name)",
                    explanation: "Последний результат выше всех предыдущих выполнений этого упражнения.",
                    priority: 100, confidence: confidence(item.observationCount), period: item.observationPeriod,
                    metrics: evidence))
            } else if item.trend == .improvement && !isCardio {
                candidates.append(PersonalInsight(id: "progress-\(subject)", category: .progress,
                    title: "Прогресс: \(item.name)",
                    explanation: "Результат улучшался в нескольких сопоставимых выполнениях.",
                    priority: 80, confidence: confidence(item.observationCount), period: item.observationPeriod,
                    metrics: evidence))
            } else if item.trend == .stable && !isCardio {
                candidates.append(PersonalInsight(id: "stable-\(subject)", category: .progress,
                    title: "Стабильный результат: \(item.name)",
                    explanation: "Последние три сопоставимых выполнения дали одинаковый результат.",
                    priority: 35, confidence: confidence(item.observationCount), period: item.observationPeriod,
                    metrics: evidence))
            }
            if analysis.readiness == .detailed, !isCardio,
               let current = item.currentPeriodChange, let prior = item.previousPeriodChange,
               abs(current - prior) >= max(1, abs(prior) * 0.2),
               (current > 0) != (prior > 0) {
                candidates.append(PersonalInsight(id: "dynamics-\(subject)", category: .progress,
                    title: "Изменилась динамика: \(item.name)",
                    explanation: "Изменение результата за период отличается от предыдущего периода.",
                    priority: 55, confidence: .strong, period: comparisonInterval,
                    metrics: [metric("Изменение за период", current, unit),
                              metric("Изменение в прошлом периоде", prior, unit)]))
            }
        }

        if analysis.readiness == .detailed {
            let total = analysis.groups.reduce(0) { $0 + $1.directSets }
            let previousTotal = analysis.groups.reduce(0) { $0 + $1.previousDirectSets }
            if total > 0 && previousTotal > 0 {
                for group in analysis.groups where group.canComparePeriods {
                    let difference = Double(group.directSets) / Double(total)
                        - Double(group.previousDirectSets) / Double(previousTotal)
                    guard abs(difference) >= 0.1 else { continue }
                    candidates.append(PersonalInsight(id: "distribution-\(group.target.category)",
                        category: .muscleStructure,
                        title: "Изменилась доля: \(group.target.category.rawValue)",
                        explanation: "Доля прямых подходов этой группы в выбранном периоде \(difference > 0 ? "выросла" : "снизилась") относительно прошлого.",
                        priority: 60, confidence: confidence(group.observationCount, comparable: true), period: comparisonInterval,
                        metrics: [metric("Прямые подходы", Double(group.directSets)),
                                  metric("В прошлом периоде", Double(group.previousDirectSets)),
                                  metric("Доля сейчас", Double(group.directSets) / Double(total) * 100, "%"),
                                  metric("Доля ранее", Double(group.previousDirectSets) / Double(previousTotal) * 100, "%")]))
                }
            }
            for accent in analysis.accents where accent.canComparePeriods {
                let change = accent.directSets - accent.previousDirectSets
                guard abs(change) >= 2, accent.directSets > 0, accent.previousDirectSets > 0,
                      let name = accent.target.accent else { continue }
                // An accent identical to its whole group is the same observation, not a second insight.
                if let group = analysis.groups.first(where: { $0.target.category == accent.target.category }),
                   group.directSets == accent.directSets,
                   group.previousDirectSets == accent.previousDirectSets { continue }
                candidates.append(PersonalInsight(id: "accent-\(accent.target.category)-\(name)",
                    category: .muscleStructure, title: "\(name): изменение акцента",
                    explanation: "Прямые подходы на этот акцент \(change > 0 ? "встречались чаще" : "встречались реже"), чем в прошлом периоде.",
                    priority: 45, confidence: confidence(accent.observationCount, comparable: true), period: comparisonInterval,
                    metrics: [metric("Прямые подходы", Double(accent.directSets)),
                              metric("В прошлом периоде", Double(accent.previousDirectSets))]))
            }
        }

        for group in analysis.groups where group.directSets > 0 && group.indirectSets >= 2 && group.trainingDays >= 2 {
            candidates.append(PersonalInsight(id: "indirect-\(group.target.category)",
                category: .muscleStructure, title: "Косвенная работа: \(group.target.category.rawValue)",
                explanation: "Помимо \(group.directSets) прямых подходов, группа участвовала косвенно в \(group.indirectSets) подходах за \(group.trainingDays) тренировочных дня. Эти виды работы учитываются отдельно.",
                priority: 25, confidence: confidence(group.observationCount), period: interval,
                metrics: [metric("Прямые подходы", Double(group.directSets)),
                          metric("Косвенные подходы", Double(group.indirectSets)),
                          metric("Тренировочные дни", Double(group.trainingDays))]))
        }

        let regularity = analysis.regularity
        if regularity.consecutiveActiveWeeks >= 2 {
            candidates.append(PersonalInsight(id: "active-week-streak", category: .regularity,
                title: "Серия активных недель",
                explanation: "Активность сохраняется \(regularity.consecutiveActiveWeeks) недели подряд.",
                priority: 50, confidence: confidence(regularity.consecutiveActiveWeeks),
                period: regularity.streakPeriod ?? interval,
                metrics: [metric("Активные недели подряд", Double(regularity.consecutiveActiveWeeks))]))
        }
        if analysis.readiness == .detailed, regularity.canComparePeriods,
           let change = regularity.workoutChange, abs(change) >= 2,
           regularity.previousWorkoutCount > 0 {
            candidates.append(PersonalInsight(id: "training-frequency", category: .regularity,
                title: "Частота тренировок изменилась",
                explanation: "В выбранном периоде \(regularity.workoutCount) тренировок, в прошлом — \(regularity.previousWorkoutCount).",
                priority: 40, confidence: confidence(regularity.observationCount, comparable: true), period: comparisonInterval,
                metrics: [metric("Тренировки", Double(regularity.workoutCount)),
                          metric("В прошлом периоде", Double(regularity.previousWorkoutCount))]))
        }
        if let missed = regularity.inactiveWeeksBeforeReturn, regularity.workoutCount > 0 {
            candidates.append(PersonalInsight(id: "return-after-break", category: .regularity,
                title: "Возвращение к тренировкам",
                explanation: "После перерыва в \(missed) полные недели снова есть записанная тренировка.",
                priority: 65, confidence: .supported, period: regularity.returnPeriod ?? interval,
                metrics: [metric("Полные недели перерыва", Double(missed)),
                          metric("Тренировки выбранного периода", Double(regularity.workoutCount))]))
        }

        var seen = Set<String>()
        let selected = candidates.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
            .filter { candidate in
                let key = candidate.id.hasPrefix("indirect-") ? "indirect-work" : candidate.id.replacingOccurrences(of: "pr-exercise-", with: "exercise-")
                    .replacingOccurrences(of: "progress-exercise-", with: "exercise-")
                    .replacingOccurrences(of: "stable-exercise-", with: "exercise-")
                    .replacingOccurrences(of: "dynamics-exercise-", with: "exercise-")
                return seen.insert(key).inserted
            }
        return PersonalInsightsResult(readiness: analysis.readiness,
                                      observationCount: analysis.observationCount,
                                      insights: Array(selected.prefix(5)))
    }
}

struct PersonalInsight: Identifiable {
    let id: String
    let category: PersonalInsightCategory
    let title: String
    let explanation: String
    let priority: Int
    let confidence: PersonalInsightConfidence
    let period: DateInterval
    let metrics: [PersonalInsightMetric]
}

struct PersonalInsightsResult {
    let readiness: MuscleAnalysisReadiness
    let observationCount: Int
    let insights: [PersonalInsight]
}

struct Insight: Identifiable {
    let id: String
    let title: String
    let message: String
    let detail: String
    let symbol: String
}

struct ExerciseProgress: Identifiable {
    let id: UUID
    let name: String
    let latest: String
    let previous: String
    let changePercent: Int
    let date: Date
}

struct ExerciseRecord: Identifiable {
    let id: String
    let name: String
    let kind: String
    let result: String
    let date: Date
}

struct CategoryBalance: Identifiable {
    let category: ExerciseCategory
    let count: Int
    let percent: Int
    var id: ExerciseCategory { category }
}

struct RegularityWeek: Identifiable {
    let index: Int
    let label: String
    let count: Int
    var id: Int { index }
}

struct InsightsSnapshot {
    let featured: Insight?
    let progress: [ExerciseProgress]
    let records: [ExerciseRecord]
    let balance: [CategoryBalance]
    let weeks: [RegularityWeek]
    let regularityComparison: String?
    let observations: [Insight]
}

@MainActor enum InsightsEngine {
    private struct Session {
        let workoutID: UUID
        let exerciseID: UUID
        let name: String
        let date: Date
        let trackingType: ExerciseTrackingType
        var sets: [SetEntry]
    }

    private struct Effort {
        let set: SetEntry
        let score: Double
    }

    static func snapshot(workouts: [WorkoutRecord], definitions: [ExerciseDefinition], now: Date = .now) -> InsightsSnapshot {
        let calendar = WorkoutStore.statisticsCalendar
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let history = workouts.filter { workout in
            !workout.isTemplate && workout.date <= now && workout.exercises.contains { exercise in
                exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
            }
        }
        let recentWorkouts = history.filter { $0.date >= cutoff }
        let categories = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.category) })
        let maps = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            (definition.id, MuscleMap(primaryGroup: definition.trackingType == .cardio ? nil : definition.category,
                                      primaryAccent: definition.muscleAccent,
                                      secondaryMuscles: definition.secondaryMuscles))
        })
        let analysis = MuscleAnalysisEngine.analyze(workouts: history, muscleMaps: maps, period: .month, relativeTo: now)
        let personal = personalInsights(from: analysis)
        let sessions = groupedSessions(history)
        let progress = progressItems(sessions: sessions, cutoff: cutoff)
        let records = recordItems(sessions: sessions)
        let balance = balanceItems(workouts: recentWorkouts, categories: categories)
        let weeks = regularityWeeks(workouts: history, now: now, calendar: calendar)
        let regularityComparison = comparableWeeklyChange(workouts: history, now: now, calendar: calendar)
        let stale = staleCategory(workouts: history, categories: categories, now: now, calendar: calendar)

        var observations: [Insight] = []
        if recentWorkouts.count >= 2 {
            observations.append(Insight(id: "frequency", title: "За 30 дней", message: "\(recentWorkouts.count) тренировок", detail: "По сохранённой истории", symbol: "calendar"))
        }
        if let top = balance.first, top.count >= 2 {
            observations.append(Insight(id: "balance", title: "Чаще всего", message: top.category.rawValue, detail: "\(top.percent)% записанных упражнений за 30 дней", symbol: "chart.bar"))
        }
        if let stale { observations.append(stale) }

        let featured = personal.insights.first.map { item in
            Insight(id: item.id, title: item.title, message: item.explanation,
                    detail: "По записанным результатам", symbol: item.category == .achievement ? "trophy" : "chart.bar")
        }

        return InsightsSnapshot(featured: featured, progress: progress, records: records, balance: balance, weeks: weeks, regularityComparison: regularityComparison, observations: observations)
    }

    private static func groupedSessions(_ workouts: [WorkoutRecord]) -> [UUID: [Session]] {
        var result: [UUID: [Session]] = [:]
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            for exercise in workout.exercises {
                if let index = result[exercise.exerciseID]?.firstIndex(where: { $0.workoutID == workout.id }) {
                    result[exercise.exerciseID]?[index].sets += exercise.sets
                } else {
                    result[exercise.exerciseID, default: []].append(Session(workoutID: workout.id, exerciseID: exercise.exerciseID, name: exercise.name, date: workout.date, trackingType: exercise.trackingType, sets: exercise.sets))
                }
            }
        }
        return result
    }

    private static func bestEffort(_ session: Session) -> Effort? {
        session.sets.compactMap { set in
            switch session.trackingType {
            case .weightReps:
                guard set.hasRecordedResult(for: .weightReps), (1...12).contains(set.repetitions) else { return nil }
                return Effort(set: set, score: set.weight * (1 + Double(set.repetitions) / 30))
            case .reps:
                guard set.repetitions > 0 else { return nil }
                return Effort(set: set, score: Double(set.repetitions))
            case .duration:
                guard set.durationSeconds > 0 else { return nil }
                return Effort(set: set, score: Double(set.durationSeconds))
            case .cardio:
                return nil
            }
        }.max(by: { $0.score < $1.score })
    }

    private static func progressItems(sessions: [UUID: [Session]], cutoff: Date) -> [ExerciseProgress] {
        sessions.compactMap { id, history in
            let recent = history.filter { $0.date >= cutoff && $0.trackingType == history.last?.trackingType }.compactMap { session -> (Session, Effort)? in
                guard let effort = bestEffort(session) else { return nil }
                return (session, effort)
            }
            guard recent.count >= 3, let latest = recent.last else { return nil }
            let previous = Array(recent.dropLast().suffix(2))
            guard previous.count == 2, previous[0].1.score > 0 else { return nil }
            let first = previous[0].1.score, second = previous[1].1.score, third = latest.1.score
            guard (first < second && second < third) || (first > second && second > third) else { return nil }
            let change = Int(((third / first) - 1) * 100)
            return ExerciseProgress(
                id: id,
                name: latest.0.name,
                latest: resultText(latest.1.set, type: latest.0.trackingType),
                previous: previous.map { resultText($0.1.set, type: $0.0.trackingType) }.joined(separator: " · "),
                changePercent: change,
                date: latest.0.date
            )
        }.sorted { abs($0.changePercent) > abs($1.changePercent) }
    }

    private static func recordItems(sessions: [UUID: [Session]]) -> [ExerciseRecord] {
        var items: [ExerciseRecord] = []
        for (id, history) in sessions where history.count >= 2 {
            guard let type = history.last?.trackingType, let name = history.last?.name else { continue }
            let matching = history.filter { $0.trackingType == type }
            guard matching.count >= 2 else { continue }
            if type != .weightReps {
                let efforts = matching.compactMap { session -> (Session, Effort)? in
                    guard let effort = bestEffort(session) else { return nil }
                    return (session, effort)
                }
                if let best = efforts.max(by: { $0.1.score < $1.1.score }) {
                    let kind = type == .duration ? "Максимальная длительность" : "Максимум повторений"
                    items.append(ExerciseRecord(id: "best-\(id)", name: name, kind: kind, result: resultText(best.1.set, type: type), date: best.0.date))
                }
                continue
            }
            let all = matching.flatMap { session in session.sets.map { (session, $0) } }
            let valid = all.filter { $0.1.hasRecordedResult(for: .weightReps) }
            if let maximum = valid.max(by: { $0.1.weight < $1.1.weight }) {
                items.append(ExerciseRecord(id: "weight-\(id)", name: name, kind: "Максимальный вес", result: resultText(maximum.1, type: type), date: maximum.0.date))
            }
            let efforts = matching.compactMap { session -> (Session, Effort)? in
                guard let effort = bestEffort(session) else { return nil }
                return (session, effort)
            }
            if let best = efforts.max(by: { $0.1.score < $1.1.score }) {
                items.append(ExerciseRecord(id: "strength-\(id)", name: name, kind: "Лучший силовой результат", result: resultText(best.1.set, type: type), date: best.0.date))
            }
            let byWeight = Dictionary(grouping: valid, by: { $0.1.weight })
            let repeatedWeights = byWeight.values.filter { Set($0.map { $0.0.workoutID }).count >= 2 }
            if let bestReps = repeatedWeights.flatMap({ $0 }).max(by: { $0.1.repetitions < $1.1.repetitions }) {
                items.append(ExerciseRecord(id: "reps-\(id)", name: name, kind: "Повторения при одном весе", result: resultText(bestReps.1, type: type), date: bestReps.0.date))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    private static func recentPersonalRecord(sessions: [UUID: [Session]], now: Date, calendar: Calendar) -> Insight? {
        let cutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let candidates: [(Date, Insight)] = sessions.values.compactMap { history in
            guard history.count >= 2, let latest = history.last, latest.date >= cutoff else { return nil }
            let prior = history.dropLast().filter { $0.trackingType == latest.trackingType }
            guard !prior.isEmpty else { return nil }
            if latest.trackingType != .weightReps {
                guard let latestEffort = bestEffort(latest),
                      let previousBest = prior.compactMap(bestEffort(_:)).map(\.score).max(),
                      latestEffort.score > previousBest else { return nil }
                let detail = latest.trackingType == .duration ? "максимальная длительность" : "максимум повторений"
                let insight = Insight(id: "record-\(latest.exerciseID)", title: "Новый рекорд", message: latest.name, detail: "\(resultText(latestEffort.set, type: latest.trackingType)) — \(detail)", symbol: "trophy")
                return (latest.date, insight)
            }
            let previousSets = prior.flatMap(\.sets).filter { $0.weight > 0 && $0.repetitions > 0 }
            let latestSets = latest.sets.filter { $0.weight > 0 && $0.repetitions > 0 }
            let previousScores = prior.compactMap(bestEffort(_:)).map(\.score)
            let detail: String
            if let latestEffort = bestEffort(latest), let previousBest = previousScores.max(), latestEffort.score > previousBest {
                detail = "\(resultText(latestEffort.set, type: .weightReps)) — лучший силовой результат"
            } else if let latestWeight = latestSets.max(by: { $0.weight < $1.weight }),
                      let previousWeight = previousSets.map(\.weight).max(), latestWeight.weight > previousWeight {
                detail = "\(resultText(latestWeight, type: .weightReps)) — новый максимум веса"
            } else if let repeated = latestSets.first(where: { set in
                let priorReps = previousSets.filter { $0.weight == set.weight }.map(\.repetitions)
                return !priorReps.isEmpty && set.repetitions > (priorReps.max() ?? 0)
            }) {
                detail = "\(resultText(repeated, type: .weightReps)) — больше повторений с этим весом"
            } else {
                return nil
            }
            let insight = Insight(id: "record-\(latest.exerciseID)", title: "Новый рекорд", message: latest.name, detail: detail, symbol: "trophy")
            return (latest.date, insight)
        }
        return candidates.max(by: { $0.0 < $1.0 })?.1
    }

    private static func balanceItems(workouts: [WorkoutRecord], categories: [UUID: ExerciseCategory]) -> [CategoryBalance] {
        let known = workouts.flatMap(\.exercises).filter { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        }.compactMap { categories[$0.exerciseID] }
        guard !known.isEmpty else { return [] }
        let counts = Dictionary(grouping: known, by: { $0 }).mapValues(\.count)
        return ExerciseCategory.allCases.compactMap { category in
            guard let count = counts[category] else { return nil }
            return CategoryBalance(category: category, count: count, percent: Int((Double(count) / Double(known.count) * 100).rounded()))
        }.sorted { $0.count > $1.count }
    }

    private static func regularityWeeks(workouts: [WorkoutRecord], now: Date, calendar: Calendar) -> [RegularityWeek] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<4).compactMap { index in
            guard let start = calendar.date(byAdding: .weekOfYear, value: index - 3, to: current.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return RegularityWeek(index: index, label: index == 3 ? "Эта неделя" : "Неделя \(index + 1)", count: workouts.filter { $0.date >= start && $0.date < end }.count)
        }
    }

    private static func comparableWeeklyChange(workouts: [WorkoutRecord], now: Date, calendar: Calendar) -> String? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start),
              let previousEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else { return nil }
        let elapsedDays = calendar.dateComponents([.day], from: week.start, to: now).day ?? 0
        guard elapsedDays >= 3 else { return nil }
        let current = workouts.filter { $0.date >= week.start && $0.date <= now }.count
        let previous = workouts.filter { $0.date >= previousStart && $0.date <= previousEnd }.count
        guard current >= 2, previous >= 2 else { return nil }
        if current == previous { return "Столько же тренировок, сколько к этому дню прошлой недели" }
        return current > previous
            ? "На \(current - previous) больше, чем к этому дню прошлой недели"
            : "На \(previous - current) меньше, чем к этому дню прошлой недели"
    }

    private static func staleCategory(workouts: [WorkoutRecord], categories: [UUID: ExerciseCategory], now: Date, calendar: Calendar) -> Insight? {
        let recentActivity = workouts.filter { $0.date >= (calendar.date(byAdding: .day, value: -14, to: now) ?? now) }
        guard recentActivity.count >= 2 else { return nil }
        let grouped = Dictionary(grouping: workouts.flatMap { workout in
            workout.exercises.compactMap { exercise -> (ExerciseCategory, Date)? in
                guard let category = categories[exercise.exerciseID],
                      exercise.sets.contains(where: { $0.hasRecordedResult(for: exercise.trackingType) }) else { return nil }
                return (category, workout.date)
            }
        }, by: { $0.0 })
        let candidates = grouped.compactMap { category, entries -> (ExerciseCategory, Date, Int)? in
            guard entries.count >= 2, let last = entries.map(\.1).max() else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
            guard days >= 8 && days <= 30 else { return nil }
            return (category, last, days)
        }
        guard let item = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        return Insight(id: "stale-\(item.0.rawValue)", title: "Давно не было", message: "\(item.0.rawValue) — \(item.2) дней", detail: "Последняя запись \(item.1.formatted(date: .abbreviated, time: .omitted))", symbol: "clock")
    }

    private static func resultText(_ set: SetEntry, type: ExerciseTrackingType) -> String {
        switch type {
        case .weightReps: return "\(set.weight.formatted()) кг × \(set.repetitions)"
        case .reps: return "\(set.repetitions) повт."
        case .duration: return set.durationSeconds < 60
            ? "\(set.durationSeconds) сек"
            : String(format: "%d:%02d", set.durationSeconds / 60, set.durationSeconds % 60)
        case .cardio:
            let time = set.durationSeconds < 60 ? "\(set.durationSeconds) сек" : String(format: "%d:%02d", set.durationSeconds / 60, set.durationSeconds % 60)
            guard let distance = set.distanceKilometers, distance > 0 else { return time }
            return "\(time) · \(distance.formatted(.number.precision(.fractionLength(0...2)))) км"
        }
    }
}
