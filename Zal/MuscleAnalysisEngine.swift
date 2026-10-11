import Foundation

enum MuscleAnalysisReadiness {
    case collecting
    case insufficientData
    case preliminary
    case detailed
}

struct MuscleActivityResult: Identifiable {
    let target: MuscleTarget
    let directSets: Int
    let indirectSets: Int
    let trainingDays: Int
    let exerciseIDs: [UUID]
    let primaryAccents: [String]
    let previousDirectSets: Int
    let previousIndirectSets: Int
    let previousTrainingDays: Int
    let observationCount: Int
    let canComparePeriods: Bool

    var id: MuscleTarget { target }
    var directSetChange: Int? { canComparePeriods ? directSets - previousDirectSets : nil }
    var indirectSetChange: Int? { canComparePeriods ? indirectSets - previousIndirectSets : nil }
    var trainingDayChange: Int? { canComparePeriods ? trainingDays - previousTrainingDays : nil }
}

enum ExerciseResultMetric: Hashable {
    case estimatedOneRepMax
    case repetitions
    case durationSeconds
    case cardioDurationSeconds
    case cardioDistanceKilometers
}

enum ExerciseResultTrend {
    case insufficientData
    case improvement
    case stable
    case changed
}

struct ExerciseProgressResult: Identifiable {
    let exerciseID: UUID
    let name: String
    let metric: ExerciseResultMetric
    let latest: Double?
    let previous: Double?
    let observationCount: Int
    let canCompare: Bool
    let canInferTrend: Bool
    let trend: ExerciseResultTrend
    let isPersonalRecord: Bool
    let currentPeriodChange: Double?
    let previousPeriodChange: Double?
    let observationPeriod: DateInterval

    var id: String { "\(exerciseID.uuidString)-\(metric)" }
    var change: Double? {
        guard canCompare, let latest, let previous else { return nil }
        return latest - previous
    }
}

struct MuscleAnalysisWeek: Identifiable {
    let start: Date
    let workoutCount: Int
    var id: Date { start }
    var isActive: Bool { workoutCount > 0 }
}

struct MuscleRegularityResult {
    let workoutCount: Int
    let activeWeekCount: Int
    let weeklyFrequency: [MuscleAnalysisWeek]
    let previousWorkoutCount: Int
    let previousActiveWeekCount: Int
    let observationCount: Int
    let canComparePeriods: Bool
    let consecutiveActiveWeeks: Int
    let inactiveWeeksBeforeReturn: Int?
    let streakPeriod: DateInterval?
    let returnPeriod: DateInterval?

    var workoutChange: Int? { canComparePeriods ? workoutCount - previousWorkoutCount : nil }
    var activeWeekChange: Int? { canComparePeriods ? activeWeekCount - previousActiveWeekCount : nil }
}

struct MuscleCardioResult {
    let sessionCount: Int
    let durationSeconds: Int
    let distanceKilometers: Double
    let distanceObservationCount: Int
    let previousSessionCount: Int
    let previousDurationSeconds: Int
    let previousDistanceKilometers: Double
    let previousDistanceObservationCount: Int
    let observationCount: Int
    let canComparePeriods: Bool

    var sessionChange: Int? { canComparePeriods ? sessionCount - previousSessionCount : nil }
    var durationChange: Int? { canComparePeriods ? durationSeconds - previousDurationSeconds : nil }
    var distanceChange: Double? {
        canComparePeriods && distanceObservationCount > 0 && previousDistanceObservationCount > 0
            ? distanceKilometers - previousDistanceKilometers : nil
    }
}

struct MuscleAnalysisSnapshot {
    let period: DateInterval
    let previousPeriod: DateInterval
    let readiness: MuscleAnalysisReadiness
    let historyAgeDays: Int
    let observationCount: Int
    let groups: [MuscleActivityResult]
    let accents: [MuscleActivityResult]
    let exercises: [ExerciseProgressResult]
    let regularity: MuscleRegularityResult
    let cardio: MuscleCardioResult
}

@MainActor enum MuscleAnalysisEngine {
    private struct Activity {
        var directSets = 0
        var indirectSets = 0
        var days = Set<Date>()
        var exerciseIDs = Set<UUID>()
        var primaryAccents = Set<String>()
    }

    private struct PeriodData {
        var activities: [MuscleTarget: Activity] = [:]
        var workouts: [WorkoutRecord] = []
        var cardioSessions = 0
        var cardioDuration = 0
        var cardioDistance = 0.0
        var cardioDistanceObservations = 0
    }

    private struct Performance {
        let date: Date
        let workoutID: UUID
        let value: Double
    }

    static func analyze(store: WorkoutStore, period: StatsPeriod, relativeTo date: Date = .now) -> MuscleAnalysisSnapshot {
        let maps = Dictionary(uniqueKeysWithValues: store.exercises.compactMap { exercise in
            store.muscleMap(for: exercise.id).map { (exercise.id, $0) }
        })
        return analyze(workouts: store.workouts, muscleMaps: maps, period: period, relativeTo: date)
    }

    static func analyze(workouts: [WorkoutRecord], muscleMaps: [UUID: MuscleMap], period: StatsPeriod, relativeTo date: Date = .now) -> MuscleAnalysisSnapshot {
        let calendar = WorkoutStore.statisticsCalendar
        guard let full = calendar.dateInterval(of: period.calendarComponent, for: date),
              let previousDate = calendar.date(byAdding: .second, value: -1, to: full.start),
              let fullPrevious = calendar.dateInterval(of: period.calendarComponent, for: previousDate) else {
            let empty = DateInterval(start: date, end: date)
            return snapshot(current: PeriodData(), previous: PeriodData(), currentInterval: empty, previousInterval: empty,
                            history: [], maps: muscleMaps, calendar: calendar, asOf: date)
        }
        // DateInterval is end-exclusive; include a result recorded exactly at `date`.
        let currentEnd = min(full.end, Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.nextUp))
        let elapsed = calendar.dateComponents([.day, .hour, .minute, .second], from: full.start, to: currentEnd)
        let previousEnd = currentEnd == full.end ? fullPrevious.end
            : min(fullPrevious.end, Date(timeIntervalSinceReferenceDate:
                (calendar.date(byAdding: elapsed, to: fullPrevious.start) ?? fullPrevious.start).timeIntervalSinceReferenceDate.nextUp))
        let currentInterval = DateInterval(start: full.start, end: max(full.start, currentEnd))
        let previousInterval = DateInterval(start: fullPrevious.start, end: max(fullPrevious.start, previousEnd))
        let validHistory = workouts.filter { $0.date <= date && containsResult($0) && !$0.isTemplate }
        let current = collect(validHistory, in: currentInterval, maps: muscleMaps, calendar: calendar)
        let previous = collect(validHistory, in: previousInterval, maps: muscleMaps, calendar: calendar)
        return snapshot(current: current, previous: previous, currentInterval: currentInterval,
                        previousInterval: previousInterval, history: validHistory, maps: muscleMaps,
                        calendar: calendar, asOf: date)
    }

    private static func snapshot(current: PeriodData, previous: PeriodData, currentInterval: DateInterval,
                                 previousInterval: DateInterval, history: [WorkoutRecord], maps: [UUID: MuscleMap],
                                 calendar: Calendar, asOf date: Date) -> MuscleAnalysisSnapshot {
        let firstDay = history.map(\.date).min().map { calendar.startOfDay(for: $0) }
        let age = firstDay.map { calendar.dateComponents([.day], from: $0, to: calendar.startOfDay(for: date)).day ?? 0 } ?? 0
        let currentDays = Set(current.workouts.map { calendar.startOfDay(for: $0.date) }).count
        let previousDays = Set(previous.workouts.map { calendar.startOfDay(for: $0.date) }).count
        let readiness: MuscleAnalysisReadiness
        if firstDay == nil || age < 7 { readiness = .collecting }
        else if currentDays < 2 { readiness = .insufficientData }
        else if age >= 28 && previousDays >= 2 { readiness = .detailed }
        else { readiness = .preliminary }
        let periodComparable = readiness == .detailed

        let groups = ExerciseCategory.allCases.filter { $0 != .cardio }.map { category in
            activityResult(MuscleTarget(category), current: current, previous: previous, comparable: periodComparable)
        }
        let accents = ExerciseCategory.allCases.filter { $0 != .cardio }.flatMap { category in
            category.accents.map { accent in
                activityResult(MuscleTarget(category, accent), current: current, previous: previous, comparable: periodComparable)
            }
        }
        let exerciseResults = progressResults(history: history, in: currentInterval, previousInterval: previousInterval,
                                              firstValidDay: firstDay, calendar: calendar)
        let weeks = weeklyFrequency(current.workouts, in: currentInterval, calendar: calendar)
        let previousWeeks = weeklyFrequency(previous.workouts, in: previousInterval, calendar: calendar)
        let continuity = weekContinuity(history, asOf: date, calendar: calendar)
        let regularity = MuscleRegularityResult(workoutCount: current.workouts.count,
                                                activeWeekCount: weeks.filter(\.isActive).count,
                                                weeklyFrequency: weeks, previousWorkoutCount: previous.workouts.count,
                                                previousActiveWeekCount: previousWeeks.filter(\.isActive).count,
                                                observationCount: current.workouts.count,
                                                canComparePeriods: periodComparable,
                                                consecutiveActiveWeeks: continuity.streak,
                                                inactiveWeeksBeforeReturn: continuity.gap,
                                                streakPeriod: continuity.streakPeriod,
                                                returnPeriod: continuity.returnPeriod)
        let cardio = MuscleCardioResult(sessionCount: current.cardioSessions, durationSeconds: current.cardioDuration,
                                        distanceKilometers: current.cardioDistance,
                                        distanceObservationCount: current.cardioDistanceObservations,
                                        previousSessionCount: previous.cardioSessions,
                                        previousDurationSeconds: previous.cardioDuration,
                                        previousDistanceKilometers: previous.cardioDistance,
                                        previousDistanceObservationCount: previous.cardioDistanceObservations,
                                        observationCount: current.cardioSessions,
                                        canComparePeriods: periodComparable && current.cardioSessions >= 2 && previous.cardioSessions >= 2)
        return MuscleAnalysisSnapshot(period: currentInterval, previousPeriod: previousInterval,
                                      readiness: readiness, historyAgeDays: age,
                                      observationCount: current.workouts.count,
                                      groups: groups, accents: accents, exercises: exerciseResults,
                                      regularity: regularity, cardio: cardio)
    }

    private static func activityResult(_ target: MuscleTarget, current: PeriodData, previous: PeriodData,
                                       comparable: Bool) -> MuscleActivityResult {
        let value = current.activities[target] ?? Activity()
        let prior = previous.activities[target] ?? Activity()
        let observations = value.directSets + value.indirectSets
        return MuscleActivityResult(target: target, directSets: value.directSets,
                                    indirectSets: value.indirectSets, trainingDays: value.days.count,
                                    exerciseIDs: Array(value.exerciseIDs).sorted { $0.uuidString < $1.uuidString },
                                    primaryAccents: value.primaryAccents.sorted(),
                                    previousDirectSets: prior.directSets,
                                    previousIndirectSets: prior.indirectSets,
                                    previousTrainingDays: prior.days.count,
                                    observationCount: observations,
                                    canComparePeriods: comparable && observations >= 2 && prior.directSets + prior.indirectSets >= 2)
    }

    private static func collect(_ workouts: [WorkoutRecord], in interval: DateInterval,
                                maps: [UUID: MuscleMap], calendar: Calendar) -> PeriodData {
        var data = PeriodData()
        for workout in workouts where interval.contains(workout.date) {
            data.workouts.append(workout)
            let day = calendar.startOfDay(for: workout.date)
            for exercise in workout.exercises {
                if exercise.trackingType == .cardio {
                    if let activity = exercise.sets.first(where: { $0.hasRecordedResult(for: .cardio) }) {
                        data.cardioSessions += 1
                        data.cardioDuration += activity.durationSeconds
                        if let distance = activity.distanceKilometers, distance.isFinite, distance > 0 {
                            data.cardioDistance += distance
                            data.cardioDistanceObservations += 1
                        }
                    }
                    continue
                }
                guard let map = exercise.muscleMapSnapshot ?? maps[exercise.exerciseID], let primary = map.primaryGroup else { continue }
                let direct = MuscleTarget(primary)
                let directAccent = map.primaryAccent.map { MuscleTarget(primary, $0) }
                let secondary = Set(map.secondaryMuscles.filter { $0.category != .cardio && $0 != directAccent })
                for entry in exercise.sets where valid(entry, type: exercise.trackingType) {
                    add(direct: true, target: direct, exerciseID: exercise.exerciseID, day: day,
                        accent: map.primaryAccent, to: &data.activities)
                    if let directAccent {
                        add(direct: true, target: directAccent, exerciseID: exercise.exerciseID, day: day,
                            accent: map.primaryAccent, to: &data.activities)
                    }
                    var indirectGroups = Set<ExerciseCategory>()
                    for target in secondary {
                        add(direct: false, target: target, exerciseID: exercise.exerciseID, day: day,
                            accent: nil, to: &data.activities)
                        if target.category != primary { indirectGroups.insert(target.category) }
                    }
                    for category in indirectGroups {
                        add(direct: false, target: MuscleTarget(category), exerciseID: exercise.exerciseID, day: day,
                            accent: nil, to: &data.activities)
                    }
                }
            }
        }
        return data
    }

    private static func add(direct: Bool, target: MuscleTarget, exerciseID: UUID, day: Date,
                            accent: String?, to activities: inout [MuscleTarget: Activity]) {
        var value = activities[target] ?? Activity()
        if direct { value.directSets += 1 } else { value.indirectSets += 1 }
        value.days.insert(day)
        value.exerciseIDs.insert(exerciseID)
        if direct, let accent { value.primaryAccents.insert(accent) }
        activities[target] = value
    }

    private static func valid(_ entry: SetEntry, type: ExerciseTrackingType) -> Bool {
        entry.hasRecordedResult(for: type)
    }

    private static func containsResult(_ workout: WorkoutRecord) -> Bool {
        workout.exercises.contains { exercise in
            exercise.sets.contains { valid($0, type: exercise.trackingType) }
        }
    }

    private static func weeklyFrequency(_ workouts: [WorkoutRecord], in interval: DateInterval,
                                        calendar: Calendar) -> [MuscleAnalysisWeek] {
        guard interval.start < interval.end,
              let first = calendar.dateInterval(of: .weekOfYear, for: interval.start) else { return [] }
        var result: [MuscleAnalysisWeek] = []
        var start = first.start
        while start < interval.end {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: start), week.end > start else { break }
            let count = workouts.filter { $0.date >= max(week.start, interval.start) && $0.date < min(week.end, interval.end) }.count
            result.append(MuscleAnalysisWeek(start: week.start, workoutCount: count))
            start = week.end
        }
        return result
    }

    private static func weekContinuity(_ history: [WorkoutRecord], asOf date: Date,
                                       calendar: Calendar) -> (streak: Int, gap: Int?, streakPeriod: DateInterval?, returnPeriod: DateInterval?) {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date),
              let firstDate = history.map(\.date).min(),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDate) else { return (0, nil, nil, nil) }
        let active = Set(history.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        var cursor = thisWeek.start
        if !active.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return (0, nil, nil, nil) }
            cursor = previous
        }
        let lastActiveWeek = cursor
        var streak = 0
        var firstActiveWeek: Date?
        while cursor >= firstWeek.start && active.contains(cursor) {
            streak += 1
            firstActiveWeek = cursor
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        let streakEnd = lastActiveWeek == thisWeek.start
            ? Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.nextUp)
            : calendar.date(byAdding: .weekOfYear, value: 1, to: lastActiveWeek)
        let streakPeriod = firstActiveWeek.flatMap { start in
            streakEnd.map { DateInterval(start: start, end: $0) }
        }
        var gap: Int?
        var returnPeriod: DateInterval?
        if active.contains(thisWeek.start),
           let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
           !active.contains(previous) {
            var missed = 0
            var week = previous
            while week >= firstWeek.start && !active.contains(week) {
                missed += 1
                guard let earlier = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
                week = earlier
            }
            if missed >= 2 && active.contains(week) {
                gap = missed
                returnPeriod = DateInterval(start: week,
                    end: Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.nextUp))
            }
        }
        return (streak, gap, streakPeriod, returnPeriod)
    }

    private static func progressResults(history: [WorkoutRecord], in interval: DateInterval,
                                        previousInterval: DateInterval, firstValidDay: Date?,
                                        calendar: Calendar) -> [ExerciseProgressResult] {
        var sessions: [UUID: [ExerciseResultMetric: [Performance]]] = [:]
        var names: [UUID: String] = [:]
        for workout in history.sorted(by: { $0.date < $1.date }) where workout.date < interval.end {
            for exercise in workout.exercises {
                names[exercise.exerciseID] = exercise.name
                for metric in metrics(for: exercise.trackingType) {
                    guard let value = bestValue(exercise, metric: metric) else { continue }
                    var values = sessions[exercise.exerciseID]?[metric] ?? []
                    if let index = values.firstIndex(where: { $0.workoutID == workout.id }) {
                        if value > values[index].value {
                            values[index] = Performance(date: workout.date, workoutID: workout.id, value: value)
                        }
                    } else {
                        values.append(Performance(date: workout.date, workoutID: workout.id, value: value))
                    }
                    sessions[exercise.exerciseID, default: [:]][metric] = values
                }
            }
        }
        return sessions.keys.sorted { $0.uuidString < $1.uuidString }.flatMap { id in
            (sessions[id] ?? [:]).keys.sorted { String(describing: $0) < String(describing: $1) }.compactMap { metric -> ExerciseProgressResult? in
                let all = (sessions[id]?[metric] ?? []).sorted { $0.date < $1.date }
                guard let latestIndex = all.lastIndex(where: { interval.contains($0.date) }) else { return nil }
                let relevant = Array(all[...latestIndex])
                let latest = relevant.last?.value
                let previous = relevant.dropLast().last?.value
                let observations = relevant.count
                let canCompare = observations >= 2
                let canInferTrend = observations >= 3
                let trend: ExerciseResultTrend
                if !canInferTrend { trend = .insufficientData }
                else {
                    let last = relevant[observations - 1].value
                    let prior = relevant[observations - 2].value
                    let earlier = relevant[observations - 3].value
                    if last == prior && prior == earlier { trend = .stable }
                    else if metric != .cardioDurationSeconds && metric != .cardioDistanceKilometers && last > prior && prior > earlier {
                        trend = .improvement
                    } else { trend = .changed }
                }
                let previousBest = relevant.dropLast().map(\.value).max()
                let isRecord: Bool
                let recordEligibleDay = firstValidDay.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }
                if let latest, let previousBest, let recordEligibleDay {
                    isRecord = canCompare && relevant.last!.date >= recordEligibleDay && latest > previousBest
                }
                else { isRecord = false }
                let currentValues = all.filter { interval.contains($0.date) }.map(\.value)
                let priorValues = all.filter { previousInterval.contains($0.date) }.map(\.value)
                let currentChange = currentValues.count >= 3 ? currentValues.last! - currentValues.first! : nil
                let priorChange = priorValues.count >= 3 ? priorValues.last! - priorValues.first! : nil
                let observationPeriod = DateInterval(start: relevant.first!.date,
                    end: Date(timeIntervalSinceReferenceDate: relevant.last!.date.timeIntervalSinceReferenceDate.nextUp))
                return ExerciseProgressResult(exerciseID: id, name: names[id] ?? "Упражнение", metric: metric,
                                              latest: latest, previous: previous, observationCount: observations,
                                              canCompare: canCompare, canInferTrend: canInferTrend,
                                              trend: trend, isPersonalRecord: isRecord,
                                              currentPeriodChange: currentChange, previousPeriodChange: priorChange,
                                              observationPeriod: observationPeriod)
            }
        }
    }

    private static func metrics(for type: ExerciseTrackingType) -> [ExerciseResultMetric] {
        switch type {
        case .weightReps: [.estimatedOneRepMax]
        case .reps: [.repetitions]
        case .duration: [.durationSeconds]
        case .cardio: [.cardioDurationSeconds, .cardioDistanceKilometers]
        }
    }

    private static func bestValue(_ exercise: WorkoutExercise, metric: ExerciseResultMetric) -> Double? {
        let values: [Double] = exercise.sets.compactMap { entry in
            switch (exercise.trackingType, metric) {
            case (.weightReps, .estimatedOneRepMax):
                guard entry.hasRecordedResult(for: .weightReps), (1...12).contains(entry.repetitions) else { return nil }
                return entry.weight * (1 + Double(entry.repetitions) / 30)
            case (.reps, .repetitions): return entry.repetitions > 0 ? Double(entry.repetitions) : nil
            case (.duration, .durationSeconds), (.cardio, .cardioDurationSeconds):
                return entry.hasRecordedResult(for: exercise.trackingType) ? Double(entry.durationSeconds) : nil
            case (.cardio, .cardioDistanceKilometers):
                guard entry.hasRecordedResult(for: .cardio), let distance = entry.distanceKilometers,
                      distance.isFinite, distance > 0 else { return nil }
                return distance
            default: return nil
            }
        }
        return values.max()
    }
}
