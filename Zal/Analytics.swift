import Foundation

struct ChartObservation: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let value: Double
    let sourceSet: SetEntry?
}

enum ChartPointSelection {
    static func nearestIndex(to position: Double, positions: [Double]) -> Int? {
        guard position.isFinite else { return nil }
        var nearest: Int?
        var distance = Double.infinity
        for index in positions.indices where positions[index].isFinite {
            let candidate = abs(positions[index] - position)
            if nearest == nil || candidate < distance {
                nearest = index
                distance = candidate
            }
        }
        return nearest
    }
}

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "Неделя"
    case month = "Месяц"
    case year = "Год"
    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

struct ActivityBucket: Identifiable, Equatable {
    let index: Int
    let label: String
    let count: Int
    var period: DateInterval? = nil
    var id: Int { index }
}

struct CardioSession: Identifiable {
    let id: UUID
    let exerciseID: UUID
    let name: String
    let date: Date
    let durationSeconds: Int
    let distanceKilometers: Double?
}

struct StatisticsSnapshot {
    let workouts: [WorkoutRecord]
    let buckets: [ActivityBucket]

    var workoutCount: Int { workouts.count }
    var exerciseCount: Int { workouts.reduce(0) { count, workout in
        count + workout.exercises.filter { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        }.count
    } }
    var cardioSessions: [CardioSession] {
        workouts.flatMap { workout in
            workout.exercises.compactMap { exercise -> CardioSession? in
                guard exercise.trackingType == .cardio,
                      let activity = exercise.sets.first(where: { $0.durationSeconds > 0 }) else { return nil }
                return CardioSession(id: exercise.id, exerciseID: exercise.exerciseID, name: exercise.name,
                                     date: workout.date, durationSeconds: activity.durationSeconds,
                                     distanceKilometers: activity.distanceKilometers.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
            }
        }.sorted { $0.date < $1.date }
    }
    var cardioSessionCount: Int { cardioSessions.count }
    var cardioDurationSeconds: Int { cardioSessions.reduce(0) { $0 + $1.durationSeconds } }
    var cardioDistanceKilometers: Double { cardioSessions.reduce(0) { $0 + ($1.distanceKilometers ?? 0) } }
    var totalVolume: Double {
        workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { exerciseTotal, exercise in
                exerciseTotal + exercise.sets.reduce(0) { total, set in
                    total + (exercise.trackingType == .weightReps && set.hasRecordedResult(for: .weightReps)
                        ? set.weight * Double(set.repetitions) : 0)
                }
            }
        }
    }
}

extension WorkoutStore {
    private struct HistoryRecordMetric: Hashable {
        let exerciseID: UUID
        let type: ExerciseTrackingType
    }

    static func historyRecordCounts(in workouts: [WorkoutRecord],
                                    score: (WorkoutExercise, Bool) -> Double?) -> [UUID: Int] {
        guard let firstDate = workouts.filter({ $0.exercises.contains { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        } }).map(\.date).min(),
              let eligible = statisticsCalendar.date(byAdding: .day, value: 7, to: statisticsCalendar.startOfDay(for: firstDate)) else { return [:] }
        let ordered = workouts.sorted { $0.date < $1.date }
        var best: [HistoryRecordMetric: Double] = [:]
        var counts: [UUID: Int] = [:]
        var index = 0
        while index < ordered.count {
            let date = ordered[index].date
            var pending: [HistoryRecordMetric: Double] = [:]
            repeat {
                let workout = ordered[index]
                var current: [HistoryRecordMetric: Double] = [:]
                for exercise in workout.exercises where exercise.trackingType != .cardio {
                    guard let value = score(exercise, false) else { continue }
                    let key = HistoryRecordMetric(exerciseID: exercise.exerciseID, type: exercise.trackingType)
                    current[key] = max(current[key] ?? value, value)
                }
                counts[workout.id] = date >= eligible ? current.filter { key, value in
                    best[key].map { value > $0 } ?? false
                }.count : 0
                if !workout.isTemplate {
                    for (key, value) in current { pending[key] = max(pending[key] ?? value, value) }
                }
                index += 1
            } while index < ordered.count && ordered[index].date == date
            // Equal timestamps are not previous workouts for each other.
            for (key, value) in pending { best[key] = max(best[key] ?? value, value) }
        }
        return counts
    }

    // Retain the single-workout API; lists use the batch calculation above.
    static func historyRecordCount(for workout: WorkoutRecord, in workouts: [WorkoutRecord],
                                   score: (WorkoutExercise, Bool) -> Double?) -> Int {
        let calendar = statisticsCalendar
        guard let firstDate = workouts.filter({ $0.exercises.contains { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        } }).map(\.date).min(),
              let eligible = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: firstDate)),
              workout.date >= eligible else { return 0 }
        let earlier = workouts.filter { !$0.isTemplate && $0.date < workout.date }
        var counted = Set<String>()
        return workout.exercises.reduce(0) { total, exercise in
            guard exercise.trackingType != .cardio else { return total }
            let prior = earlier.flatMap(\.exercises).filter { $0.exerciseID == exercise.exerciseID && $0.trackingType == exercise.trackingType }
            guard !prior.isEmpty else { return total }
            let dimensions = exercise.trackingType == .cardio ? [false, true] : [false]
            return total + dimensions.filter { distance in
                guard let current = score(exercise, distance),
                      let previous = prior.compactMap({ score($0, distance) }).max(), current > previous else { return false }
                let key = "\(exercise.exerciseID.uuidString)-\(exercise.trackingType.rawValue)-\(distance)"
                return counted.insert(key).inserted
            }.count
        }
    }

    func cardioHistory(for exerciseID: UUID) -> [CardioSession] {
        StatisticsSnapshot(workouts: workouts, buckets: []).cardioSessions.filter { $0.exerciseID == exerciseID }
    }

    static var statisticsCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }

    func snapshot(for period: StatsPeriod, relativeTo date: Date = .now) -> StatisticsSnapshot {
        let calendar = Self.statisticsCalendar
        guard let interval = calendar.dateInterval(of: period.calendarComponent, for: date) else {
            return StatisticsSnapshot(workouts: [], buckets: [])
        }
        let included = workouts.filter { workout in
            workout.date >= interval.start && workout.date < interval.end && workout.date <= date && workout.exercises.contains { exercise in
                exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
            }
        }
        let buckets: [ActivityBucket]

        switch period {
        case .week:
            let labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            buckets = (0..<7).map { index in
                let day = calendar.date(byAdding: .day, value: index, to: interval.start)!
                return ActivityBucket(index: index, label: labels[index], count: included.filter { calendar.isDate($0.date, inSameDayAs: day) }.count,
                                      period: calendar.dateInterval(of: .day, for: day))
            }
        case .month:
            var monthlyBuckets: [ActivityBucket] = []
            var weekStart = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
            while weekStart < interval.end {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart),
                      week.end > weekStart else { break }
                let rangeStart = max(week.start, interval.start)
                let rangeEnd = min(week.end, interval.end)
                if rangeStart < rangeEnd,
                   let lastDay = calendar.date(byAdding: .day, value: -1, to: rangeEnd) {
                    let first = calendar.component(.day, from: rangeStart)
                    let last = calendar.component(.day, from: lastDay)
                    let count = included.filter { $0.date >= rangeStart && $0.date < rangeEnd }.count
                    monthlyBuckets.append(ActivityBucket(index: monthlyBuckets.count, label: "\(first)–\(last)", count: count,
                                                         period: DateInterval(start: rangeStart, end: rangeEnd)))
                }
                weekStart = week.end
            }
            buckets = monthlyBuckets
        case .year:
            let labels = ["Я", "Ф", "М", "А", "М", "И", "И", "А", "С", "О", "Н", "Д"]
            buckets = (0..<12).map { index in
                let start = calendar.date(byAdding: .month, value: index, to: interval.start)!
                return ActivityBucket(index: index, label: labels[index], count: included.filter { calendar.component(.month, from: $0.date) == index + 1 }.count,
                                      period: calendar.dateInterval(of: .month, for: start))
            }
        }
        return StatisticsSnapshot(workouts: included, buckets: buckets)
    }
}
