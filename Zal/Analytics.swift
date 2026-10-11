import Foundation

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

struct ActivityBucket: Identifiable {
    let index: Int
    let label: String
    let count: Int
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
            interval.contains(workout.date) && workout.exercises.contains { exercise in
                exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
            }
        }
        let buckets: [ActivityBucket]

        switch period {
        case .week:
            let labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            buckets = (0..<7).map { index in
                let day = calendar.date(byAdding: .day, value: index, to: interval.start)!
                return ActivityBucket(index: index, label: labels[index], count: included.filter { calendar.isDate($0.date, inSameDayAs: day) }.count)
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
                    monthlyBuckets.append(ActivityBucket(index: monthlyBuckets.count, label: "\(first)–\(last)", count: count))
                }
                weekStart = week.end
            }
            buckets = monthlyBuckets
        case .year:
            let labels = ["Я", "Ф", "М", "А", "М", "И", "И", "А", "С", "О", "Н", "Д"]
            buckets = (0..<12).map { index in
                ActivityBucket(index: index, label: labels[index], count: included.filter { calendar.component(.month, from: $0.date) == index + 1 }.count)
            }
        }
        return StatisticsSnapshot(workouts: included, buckets: buckets)
    }
}
