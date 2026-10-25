import Foundation

@MainActor @main
struct SplitCompletionTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func main() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("split-tests-\(UUID().uuidString).json")
        let store = WorkoutStore(fileURL: file)
        let exerciseID = UUID()
        let first = SplitWorkoutTemplate(name: "A", exercises: [
            SplitTemplateExercise(exerciseID: exerciseID, name: "Жим", trackingType: .weightReps)
        ])
        let second = SplitWorkoutTemplate(name: "B", exercises: [
            SplitTemplateExercise(exerciseID: exerciseID, name: "Жим", trackingType: .weightReps)
        ])
        store.upsertSplitTemplate(first)
        store.upsertSplitTemplate(second)
        store.setSplitEnabled(true)

        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let later = day.addingTimeInterval(86_400)
        guard var draft = store.prepareNextSplitWorkout(on: day) else { preconditionFailure("No split draft") }
        expect(store.nextSplitTemplate?.id == first.id, "Preparing must not advance the split")
        draft.exercises[0].sets = [SetEntry(weight: 40, repetitions: 0)]
        store.upsert(draft)
        expect(store.records.first(where: { $0.id == draft.id })?.splitCompletionRecorded != true,
               "Incomplete set must not complete a split")

        draft.exercises[0].sets = [SetEntry(weight: 40, repetitions: 8)]
        store.upsert(draft)
        expect(store.nextSplitTemplate?.id == first.id && store.workouts.isEmpty,
               "A valid set must not complete or advance the split")
        expect(store.prepareNextSplitWorkout(on: day)?.id == draft.id,
               "Same-day draft must reopen")
        expect(store.prepareNextSplitWorkout(on: later)?.id == draft.id,
               "Unfinished draft must reopen on a later day without losing sets")
        expect(store.records.first(where: { $0.id == draft.id })?.exercises[0].sets[0].repetitions == 8,
               "Recorded set must be preserved")
        let reloadedDraft = WorkoutStore(fileURL: file)
        expect(reloadedDraft.records.first(where: { $0.id == draft.id })?.exercises[0].sets[0].repetitions == 8 &&
               reloadedDraft.nextSplitTemplate?.id == first.id,
               "An unfinished workout and its place in the split survive reload")
        draft.splitCompletionRecorded = true
        store.upsert(draft)
        expect(store.records.first(where: { $0.id == draft.id })?.splitCompletionRecorded != true &&
               store.nextSplitTemplate?.id == first.id,
               "Saving a record cannot explicitly mark it complete")
        draft.splitCompletionRecorded = nil

        store.completeSplitWorkout(draft.id)
        expect(store.records.first(where: { $0.id == draft.id })?.splitCompletionRecorded == true,
               "Explicit completion must mark the workout")
        expect(store.nextSplitTemplate?.id == second.id && store.workouts.count == 1,
               "Explicit completion must advance exactly once")
        let reloadedCompleted = WorkoutStore(fileURL: file)
        expect(reloadedCompleted.records.first(where: { $0.id == draft.id })?.splitCompletionRecorded == true &&
               reloadedCompleted.nextSplitTemplate?.id == second.id,
               "Explicit completion and next template survive reload")
        draft.splitCompletionRecorded = false
        store.upsert(draft)
        store.completeSplitWorkout(draft.id)
        expect(store.records.first(where: { $0.id == draft.id })?.splitCompletionRecorded == true &&
               store.nextSplitTemplate?.id == second.id,
               "Editing or completing again must not advance or reopen a completed workout")

        let blank = store.prepareNextSplitWorkout(on: later)!
        store.completeSplitWorkout(blank.id)
        expect(store.nextSplitTemplate?.id == second.id,
               "A workout without valid results must not complete")
        store.skipNextSplitTemplate(on: later)
        expect(store.nextSplitTemplate?.id == first.id, "Skipping must still advance")
        expect(!store.records.contains(where: { $0.id == blank.id }), "Skipping may discard an empty draft")

        let nextDay = later.addingTimeInterval(86_400)
        var saved = store.prepareNextSplitWorkout(on: nextDay)!
        saved.exercises[0].sets = [SetEntry(weight: 45, repetitions: 5)]
        store.upsert(saved)
        store.skipNextSplitTemplate(on: nextDay)
        expect(store.nextSplitTemplate?.id == second.id &&
               store.records.contains(where: { $0.id == saved.id }),
               "Skipping must preserve a draft with recorded results")
        store.completeSplitWorkout(saved.id)
        expect(store.nextSplitTemplate?.id == second.id,
               "Completing a previously skipped draft must not advance the current template")
        testHistoricalMuscleMaps()
        testBuiltInMuscleMaps()
        testExerciseTrends()
        testInsightWording()
        testWarmupClassification()
        testRepetitionRecords()
        testExerciseOrdering()
        testChartSelection()
        testPersonalStoreStartup()
        testLoadFailureProtection()
        testNumericInputValidation()
        testDuplicateDataProtection()
        testCustomExerciseNamePreservation()
        testHistoryRecordDeduplication()
        testHistoryRecordBatch()
        testStatisticsPeriodBoundaries()
        testActiveWeekHistory()
        if ProcessInfo.processInfo.environment["GYMTREKER_RECORD_BENCHMARK"] == "1" { benchmarkHistoryRecords() }
        print("PASS: split completion, continuation, editing and skipping")
    }


    static func testActiveWeekHistory() {
        let calendar = WorkoutStore.statisticsCalendar
        let now = calendar.date(from: DateComponents(year: 2027, month: 1, day: 6, hour: 12))!
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!
        let store = WorkoutStore(isEphemeral: true)
        let definition = store.exercises[0]
        func workout(at date: Date) -> WorkoutRecord {
            WorkoutRecord(title: "Активная неделя", date: date, exercises: [
                WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [SetEntry(weight: 40, repetitions: 8)])
            ])
        }
        let empty = MuscleAnalysisEngine.activeWeekHistory(store: store, relativeTo: now)
        expect(empty.weeks.isEmpty && empty.currentStreak == 0 && empty.longestStreak == 0,
               "Empty history has no invented weeks or streaks")
        for offset in [-10, -9, -8, -7, -6, -3, -2, -1] {
            let date = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek.start)!
            store.upsert(workout(at: date))
        }
        let extra = calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeek.start)!.addingTimeInterval(3600)
        store.upsert(workout(at: extra))
        store.upsert(workout(at: now.addingTimeInterval(1)))
        store.upsert(workout(at: currentWeek.end))
        var template = workout(at: now)
        template.isTemplate = true
        store.upsert(template)
        var incomplete = workout(at: now)
        incomplete.exercises[0].sets = [SetEntry(weight: 40, repetitions: 0)]
        store.upsert(incomplete)
        var unfinishedSplit = workout(at: now)
        unfinishedSplit.splitTemplateID = UUID()
        store.upsert(unfinishedSplit)
        let originalRecords = store.records
        let report = MuscleAnalysisEngine.activeWeekHistory(store: store, relativeTo: now)
        expect(report.currentStreak == 3 && report.longestStreak == 5 && report.weeks.count == 11 &&
               report.weeks.last?.start == currentWeek.start && report.weeks.last?.workoutCount == 0 &&
               report.weeks.filter(\.isActive).count == 8 && report.weeks.reduce(0, { $0 + $1.workoutCount }) == 9,
               "All-history grid excludes future/template/incomplete/split drafts and preserves the unfinished current-week grace")
        expect(report.weeks.first { $0.start == calendar.dateInterval(of: .weekOfYear, for: extra)?.start }?.workoutCount == 2,
               "Selecting a week exposes its actual completed workout count")
        expect(report.weeks.allSatisfy { calendar.component(.weekday, from: $0.start) == 2 } &&
               Set(report.weeks.map(\.start)).count == report.weeks.count,
               "Week cells are unique Monday starts across the year boundary")
        for period in StatsPeriod.allCases {
            expect(report.currentStreak == MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: now)
                .regularity.consecutiveActiveWeeks,
                   "Sheet and main insight use the same streak rule, independently of the selected analysis period")
        }
        expect(store.records == originalRecords, "Opening/reading week history never changes saved records or dates")
        let current = workout(at: now)
        store.upsert(current)
        let active = MuscleAnalysisEngine.activeWeekHistory(store: store, relativeTo: now)
        expect(active.currentStreak == 4 && active.longestStreak == 5 && active.weeks.last?.workoutCount == 1,
               "Newly completed data updates current week and streak without including a future result")
        store.delete(current)
        let deleted = MuscleAnalysisEngine.activeWeekHistory(store: store, relativeTo: now)
        expect(deleted.currentStreak == 3 && deleted.weeks.last?.workoutCount == 0,
               "Deleting the current week's only result refreshes the sheet")
        let oldOnly = WorkoutStore(isEphemeral: true)
        for record in store.workouts where record.date < currentWeek.start { oldOnly.upsert(record) }
        let later = MuscleAnalysisEngine.activeWeekHistory(store: oldOnly, relativeTo: currentWeek.end)
        expect(later.currentStreak == 0 && later.longestStreak == 5 && later.weeks.last?.start == currentWeek.end,
               "A completed missed week breaks the current streak, not the historical best")
        let futureOnly = WorkoutStore(isEphemeral: true)
        futureOnly.upsert(workout(at: currentWeek.end))
        expect(MuscleAnalysisEngine.activeWeekHistory(store: futureOnly, relativeTo: now).weeks.isEmpty,
               "Future-only records keep the empty state")
        let boundary = MuscleAnalysisEngine.activeWeekHistory(store: futureOnly, relativeTo: currentWeek.end)
        expect(boundary.weeks.count == 1 && boundary.currentStreak == 1 && boundary.longestStreak == 1 &&
               boundary.weeks[0].start == currentWeek.end && boundary.weeks[0].workoutCount == 1,
               "A Monday 00:00 workout belongs only to that new week")
        print("PASS: active-week sheet data, all-history best, unfinished-week grace, empty/zero streak, future records and year/Monday boundaries")
    }

    static func testStatisticsPeriodBoundaries() {
        // This changes only the test process's calendar default, never the device's settings.
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        let definition = ExerciseDefinition.builtIn[0]
        func record(at date: Date) -> WorkoutRecord {
            WorkoutRecord(title: "Граница периода", date: date, exercises: [
                WorkoutExercise(exerciseID: definition.id, name: definition.name,
                                sets: [SetEntry(weight: 40, repetitions: 8)])
            ])
        }
        for zone in ["Europe/Moscow", "America/New_York", "Pacific/Kiritimati"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            let calendar = WorkoutStore.statisticsCalendar
            expect(calendar.timeZone.identifier == zone && calendar.firstWeekday == 2,
                   "Statistics use the local timezone and Monday as the first weekday")
            for (year, month, day) in [(2026, 10, 7), (2026, 12, 31), (2027, 1, 1),
                                       (2024, 2, 29), (2026, 3, 8), (2026, 11, 1)] {
                let anchor = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
                for period in StatsPeriod.allCases {
                    let interval = calendar.dateInterval(of: period.calendarComponent, for: anchor)!
                    let now = interval.end.addingTimeInterval(-1)
                    let dates = [interval.start.addingTimeInterval(-1), interval.start,
                                 interval.start.addingTimeInterval(1), now, interval.end,
                                 interval.end.addingTimeInterval(1)]
                    let store = WorkoutStore(isEphemeral: true)
                    for date in dates { store.upsert(record(at: date)) }
                    let originals = store.records
                    let stats = store.snapshot(for: period, relativeTo: now)
                    let muscle = MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: now)
                    expect(Set(stats.workouts.map(\.date)) == Set([interval.start, interval.start.addingTimeInterval(1), now]) &&
                           stats.workoutCount == stats.buckets.reduce(0, { $0 + $1.count }) &&
                           stats.workoutCount == muscle.regularity.workoutCount &&
                           stats.workoutCount == muscle.regularity.weeklyFrequency.reduce(0, { $0 + $1.workoutCount }),
                           "Counts and bars share half-open boundaries: \(zone), \(period.rawValue), \(anchor)")
                    expect(stats.totalVolume == Double(stats.workoutCount * 320) &&
                           muscle.groups.reduce(0, { $0 + $1.directSets }) == stats.workoutCount,
                           "Volume and direct-set measures retain their distinct meanings")
                    for asOf in [interval.start, interval.end] {
                        let nextStats = store.snapshot(for: period, relativeTo: asOf)
                        let nextMuscle = MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: asOf)
                        expect(nextStats.workoutCount == 1 && nextStats.workouts[0].date == asOf &&
                               nextStats.buckets.reduce(0, { $0 + $1.count }) == 1 && nextMuscle.regularity.workoutCount == 1,
                               "An exact boundary belongs only to its new period, and later records are future data")
                    }
                    let firstInterval = MuscleAnalysisEngine.analyze(store: WorkoutStore(isEphemeral: true), period: period, relativeTo: anchor)
                    let previous = WorkoutStore(isEphemeral: true)
                    previous.upsert(record(at: firstInterval.previousPeriod.end.addingTimeInterval(-1)))
                    previous.upsert(record(at: firstInterval.previousPeriod.end))
                    let comparison = MuscleAnalysisEngine.analyze(store: previous, period: period, relativeTo: anchor)
                    expect(comparison.regularity.previousWorkoutCount == 1,
                           "The equal elapsed portion of the previous period also excludes its end")
                    expect(store.records == originals, "Filtering must not alter stored dates, future records, sets or UUIDs")
                }
            }
            let future = WorkoutStore(isEphemeral: true)
            future.upsert(record(at: Date().addingTimeInterval(3600)))
            expect(future.thisWeekCount == 0 && future.thisWeekActivity.reduce(0, +) == 0 && future.streakWeeks == 0,
                   "Future workouts cannot create current home statistics or an active-week streak")
        }
        // The same absolute timestamps change calendar membership, not their saved dates, after a timezone change.
        let parser = ISO8601DateFormatter()
        let saved = record(at: parser.date(from: "2026-12-31T22:30:00Z")!)
        let asOf = parser.date(from: "2027-01-01T12:00:00Z")!
        let store = WorkoutStore(isEphemeral: true)
        store.upsert(saved)
        let originals = store.records
        for (zone, expected) in [("Europe/Moscow", 1), ("America/New_York", 0), ("Pacific/Kiritimati", 1)] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            for period in [StatsPeriod.month, .year] {
                expect(store.snapshot(for: period, relativeTo: asOf).workoutCount == expected &&
                       MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: asOf).regularity.workoutCount == expected,
                       "Both engines update calendar membership after a timezone change")
            }
            expect(store.records == originals, "Timezone changes must not redate workouts")
        }
        print("PASS: half-open weeks/months/years, Monday midnight, leap/year/DST boundaries, future records, elapsed comparisons and timezone changes")
    }

    static func historyRecordScore(_ exercise: WorkoutExercise, _: Bool) -> Double? {
        exercise.analysisSets.compactMap { set -> Double? in
            switch exercise.trackingType {
            case .weightReps:
                guard set.hasRecordedResult(for: .weightReps), (1...12).contains(set.repetitions) else { return nil }
                return set.weight * (1 + Double(set.repetitions) / 30)
            case .reps: return set.repetitions > 0 ? Double(set.repetitions) : nil
            case .duration: return set.durationSeconds > 0 ? Double(set.durationSeconds) : nil
            case .cardio: return nil
            }
        }.max()
    }

    static func historyRecordFixture(count: Int) -> [WorkoutRecord] {
        let calendar = WorkoutStore.statisticsCalendar
        let start = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 12))!
        let definitions = Array(ExerciseDefinition.builtIn.prefix(6))
        return (0..<count).map { index in
            var exercises = definitions.enumerated().map { position, definition in
                let weight = Double(40 + position * 5 + index / 12 + [0, 2, -1, 1, 0][index % 5])
                return WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [
                    SetEntry(weight: 10, repetitions: 10), SetEntry(weight: weight, repetitions: 8),
                    SetEntry(weight: weight, repetitions: 7)
                ])
            }
            if index % 4 == 0 {
                var repeated = exercises[0]
                repeated.id = UUID()
                exercises.append(repeated)
            }
            return WorkoutRecord(id: UUID(uuidString: String(format: "F0000000-0000-4000-8000-%012X", index + 1))!,
                                 title: "Синтетическая история \(index)",
                                 date: calendar.date(byAdding: .day, value: index, to: start)!, exercises: exercises)
        }
    }

    static func checkHistoryRecordBatch(_ history: [WorkoutRecord]) {
        let counts = WorkoutStore.historyRecordCounts(in: history, score: historyRecordScore)
        for workout in history {
            expect(counts[workout.id, default: 0] == WorkoutStore.historyRecordCount(for: workout, in: history, score: historyRecordScore),
                   "Batch result must exactly match the previous implementation for \(workout.title)")
        }
    }

    static func testHistoryRecordBatch() {
        var history = historyRecordFixture(count: 35)
        checkHistoryRecordBatch(history)
        checkHistoryRecordBatch(Array(history.reversed()))
        var peer = history.last!
        peer.id = UUID()
        peer.title = "То же время — не предыдущая тренировка"
        peer.exercises[0].sets = [SetEntry(weight: 200, repetitions: 8)]
        history.append(peer)
        var template = peer
        template.id = UUID()
        template.isTemplate = true
        template.date = history[0].date.addingTimeInterval(-10 * 86_400)
        history.append(template)
        var mixed = peer
        mixed.id = UUID()
        mixed.exercises += [
            WorkoutExercise(exerciseID: mixed.exercises[0].exerciseID, name: "Другой показатель", sets: [SetEntry(repetitions: 12)], trackingType: .reps),
            WorkoutExercise(exerciseID: UUID(), name: "Только кардио", sets: [SetEntry(durationSeconds: 600)], trackingType: .cardio),
            WorkoutExercise(exerciseID: UUID(), name: "Пустое упражнение", sets: [])
        ]
        history.append(mixed)
        checkHistoryRecordBatch(history)
        let store = WorkoutStore(isEphemeral: true)
        for workout in history where !workout.isTemplate { store.upsert(workout) }
        checkHistoryRecordBatch(store.workouts)
        var edited = store.workouts.first!
        edited.date = history[0].date.addingTimeInterval(1)
        edited.exercises[0].sets = [SetEntry(weight: 250, repetitions: 8)]
        store.upsert(edited)
        checkHistoryRecordBatch(store.workouts)
        store.delete(edited)
        checkHistoryRecordBatch(store.workouts)
        expect(WorkoutStore.historyRecordCounts(in: [], score: historyRecordScore).isEmpty,
               "Empty history produces no record counts")
        var calls = 0
        _ = WorkoutStore.historyRecordCounts(in: history) { exercise, distance in
            calls += 1
            return historyRecordScore(exercise, distance)
        }
        expect(calls == history.flatMap(\.exercises).filter { $0.trackingType != .cardio }.count,
               "Each row's working sets and best score are calculated once for the whole history")
        print("PASS: batch record counts match original results; equal dates, duplicate rows, templates, add/edit/delete and one score per row")
    }

    static func benchmarkHistoryRecords() {
        for size in [100, 1500] {
            let history = historyRecordFixture(count: size)
            let before = history
            let oldStart = ProcessInfo.processInfo.systemUptime
            let expected = history.map { WorkoutStore.historyRecordCount(for: $0, in: history, score: historyRecordScore) }
            let oldSeconds = ProcessInfo.processInfo.systemUptime - oldStart
            let newStart = ProcessInfo.processInfo.systemUptime
            let counts = WorkoutStore.historyRecordCounts(in: history, score: historyRecordScore)
            let newSeconds = ProcessInfo.processInfo.systemUptime - newStart
            expect(history.enumerated().allSatisfy { counts[$0.element.id, default: 0] == expected[$0.offset] } && history == before,
                   "All \(size) benchmark results must match exactly without mutating data")
            print(String(format: "BENCHMARK %d workouts: old %.6f s, batch %.6f s, %.1fx faster; all counts equal", size, oldSeconds, newSeconds, oldSeconds / max(newSeconds, 0.000000001)))
        }
    }

    static func testHistoryRecordDeduplication() {
        let calendar = WorkoutStore.statisticsCalendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        let currentDate = calendar.date(byAdding: .day, value: 10, to: start)!
        let strengthID = ExerciseDefinition.builtIn.first { $0.name == "Жим штанги лёжа" }!.id
        let repsID = ExerciseDefinition.builtIn.first { $0.trackingType == .reps }!.id
        let durationID = ExerciseDefinition.builtIn.first { $0.trackingType == .duration }!.id
        func strength(_ weight: Double) -> WorkoutExercise {
            WorkoutExercise(exerciseID: strengthID, name: "Жим", sets: [SetEntry(weight: weight, repetitions: 8)])
        }
        func reps(_ count: Int) -> WorkoutExercise {
            WorkoutExercise(exerciseID: repsID, name: "Повторения", sets: [SetEntry(repetitions: count)], trackingType: .reps)
        }
        func duration(_ seconds: Int, id: UUID? = nil) -> WorkoutExercise {
            WorkoutExercise(exerciseID: id ?? durationID, name: "Время", sets: [SetEntry(durationSeconds: seconds)], trackingType: .duration)
        }
        // The unchanged UI scorer supplies one comparable result per row, using its own working sets.
        func score(_ exercise: WorkoutExercise, _: Bool) -> Double? {
            exercise.analysisSets.compactMap { set -> Double? in
                switch exercise.trackingType {
                case .weightReps:
                    guard set.hasRecordedResult(for: .weightReps), (1...12).contains(set.repetitions) else { return nil }
                    return set.weight * (1 + Double(set.repetitions) / 30)
                case .reps: return set.repetitions > 0 ? Double(set.repetitions) : nil
                case .duration: return set.durationSeconds > 0 ? Double(set.durationSeconds) : nil
                case .cardio: return nil
                }
            }.max()
        }
        let baseline = WorkoutRecord(title: "База", date: start, exercises: [strength(40), reps(8), duration(60)])
        func verify(_ exercises: [WorkoutExercise], expected: Int, name: String) {
            let current = WorkoutRecord(title: name, date: currentDate, exercises: exercises)
            let history = [baseline, current]
            expect(WorkoutStore.historyRecordCount(for: current, in: history, score: score) == expected,
                   "History count: \(name)")
            expect(WorkoutStore.historyRecordCounts(in: history, score: score)[current.id, default: 0] == expected,
                   "Batch history count: \(name)")
            let store = WorkoutStore(isEphemeral: true)
            store.upsert(baseline)
            store.upsert(current)
            let saved = store.records
            let analysis = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: currentDate)
            expect(analysis.exercises.filter(\.isPersonalRecord).count == expected,
                   "History counter must agree with the main comparable-result analysis: \(name)")
            expect(store.records == saved && current.exercises == exercises,
                   "Counting must not merge rows, change sets/UUIDs or mutate history")
        }
        verify([strength(50), strength(50)], expected: 1, name: "Одинаковый рекорд в двух строках")
        verify([strength(50), strength(60)], expected: 1, name: "Разные улучшения одного показателя")
        verify([strength(35), strength(50)], expected: 1, name: "Рекорд только во второй строке")
        verify([strength(50), strength(35)], expected: 1, name: "Рекорд только в первой строке")
        verify([strength(40), strength(35), reps(8)], expected: 0, name: "Рекордов нет")
        verify([strength(50), reps(10)], expected: 2, name: "Два разных упражнения")
        verify([strength(50), strength(60), reps(10), reps(11), duration(90), duration(100)],
               expected: 3, name: "Три действительных рекорда без повторов")
        verify([WorkoutExercise(exerciseID: strengthID, name: "Пустая строка", sets: []), strength(50)],
               expected: 1, name: "Пустая первая строка не скрывает рекорд")
        var warmup = strength(50)
        warmup.sets = [SetEntry(weight: 10, repetitions: 10), SetEntry(weight: 20, repetitions: 10),
                      SetEntry(weight: 50, repetitions: 8), SetEntry(weight: 50, repetitions: 8)]
        verify([warmup, strength(50)], expected: 1, name: "Рабочие подходы классифицируются по прежним правилам")

        let typedBaseline = WorkoutRecord(title: "Разные виды показателя", date: start,
                                          exercises: [reps(8), duration(60, id: repsID)])
        let typedCurrent = WorkoutRecord(title: "Два вида рекорда одного ID", date: currentDate,
                                         exercises: [reps(10), reps(11), duration(90, id: repsID), duration(100, id: repsID)])
        expect(WorkoutStore.historyRecordCount(for: typedCurrent, in: [typedBaseline, typedCurrent], score: score) == 2,
               "Different comparable metrics for the same exercise ID are not deduplicated against each other")
        expect(WorkoutStore.historyRecordCounts(in: [typedBaseline, typedCurrent], score: score)[typedCurrent.id] == 2,
               "Batch counts also preserve distinct metric records for the same exercise ID")
        let typedStore = WorkoutStore(isEphemeral: true)
        typedStore.upsert(typedBaseline)
        typedStore.upsert(typedCurrent)
        expect(MuscleAnalysisEngine.analyze(store: typedStore, period: .month, relativeTo: currentDate)
            .exercises.filter(\.isPersonalRecord).count == 2, "Distinct metric records agree with progress analysis")
        let early = WorkoutRecord(title: "Сбор истории", date: start.addingTimeInterval(86_400), exercises: [strength(50), strength(60)])
        expect(WorkoutStore.historyRecordCount(for: early, in: [baseline, early], score: score) == 0,
               "The existing seven-day collection threshold is unchanged")
        let newID = WorkoutExercise(exerciseID: UUID(), name: "Без базы", sets: [SetEntry(weight: 80, repetitions: 8)])
        let noBaseline = WorkoutRecord(title: "Первое выполнение", date: currentDate, exercises: [newID])
        expect(WorkoutStore.historyRecordCount(for: noBaseline, in: [baseline, noBaseline], score: score) == 0,
               "A first-ever exercise result is still not a record")
        print("PASS: history record deduplication, different exercises/metrics, no records, working sets and progress consistency")
    }

    static func testCustomExerciseNamePreservation() {
        struct Fixture: Encodable {
            var records: [WorkoutRecord]
            var exercises: [ExerciseDefinition]
            var weeklyGoal = 4
            var splitPlan: SplitPlan
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("custom-name-load-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workouts.json")
        let builtin = ExerciseDefinition.builtIn.first { $0.name == "Бабочка" }!
        let custom = ExerciseDefinition(name: "Бабочка", category: .back, illustrationID: "custom-butterfly.png",
                                        trackingType: .reps, muscleAccent: "Широчайшие",
                                        secondaryMuscles: [MuscleTarget(.biceps, "Брахиалис")])
        let other = ExerciseDefinition(name: "Собственная тяга", category: .back, muscleAccent: "Средняя часть спины")
        var outdatedBuiltin = builtin
        outdatedBuiltin.name = "Старое название встроенного упражнения"
        outdatedBuiltin.category = .legs
        outdatedBuiltin.muscleAccent = "Передняя поверхность бедра"
        let canonicalBench = ExerciseDefinition.builtIn.first { $0.name == "Жим штанги лёжа" }!
        let legacyBuiltin = ExerciseDefinition(name: canonicalBench.name, category: .legs, isCustom: false)
        let unknown = ExerciseDefinition(name: "Неизвестное встроенное упражнение", category: .forearms, isCustom: false)
        let snapshot = MuscleMap(primaryGroup: .shoulders, primaryAccent: "Задняя дельта", secondaryMuscles: [])
        let record = WorkoutRecord(title: "История", exercises: [
            WorkoutExercise(exerciseID: custom.id, name: custom.name, sets: [SetEntry(repetitions: 10)], trackingType: .reps),
            WorkoutExercise(exerciseID: other.id, name: other.name, sets: [SetEntry(weight: 30, repetitions: 8)], muscleMapSnapshot: snapshot),
            WorkoutExercise(exerciseID: builtin.id, name: builtin.name, sets: [SetEntry(weight: 45, repetitions: 8)]),
            WorkoutExercise(exerciseID: legacyBuiltin.id, name: legacyBuiltin.name, sets: [SetEntry(weight: 60, repetitions: 8)])
        ], note: "Исходная заметка")
        let template = WorkoutRecord(title: "Шаблон", exercises: [
            WorkoutExercise(exerciseID: custom.id, name: custom.name, trackingType: custom.trackingType)
        ], isTemplate: true)
        let split = SplitPlan(templates: [SplitWorkoutTemplate(name: "A", exercises: [
            SplitTemplateExercise(exerciseID: custom.id, name: custom.name, trackingType: custom.trackingType)
        ])])
        let fixture = Fixture(records: [record, template], exercises: [custom, other, outdatedBuiltin, legacyBuiltin, unknown], splitPlan: split)
        let original = try! JSONEncoder().encode(fixture)
        try! original.write(to: url)
        let store = WorkoutStore(fileURL: url)
        expect(store.loadError == nil && (try! Data(contentsOf: url)) == original,
               "Loading same-name custom/built-in exercises must not rewrite the source file")
        expect(store.exercises.first { $0.id == custom.id } == custom &&
               store.exercises.first { $0.id == other.id } == other &&
               store.exercises.first { $0.id == unknown.id } == unknown,
               "Custom definitions and unrecognized definitions keep every stored field")
        expect(store.exercises.first { $0.id == builtin.id } == builtin &&
               store.exercises.filter { $0.name == builtin.name }.count == 2 &&
               store.exercises.filter { $0.id == custom.id }.count == 1 &&
               Set(store.exercises.map(\.id)).count == store.exercises.count,
               "Same-name exercises with different identities stay separate, without duplicating either identity")
        var expectedLegacy = canonicalBench
        expectedLegacy.id = legacyBuiltin.id
        expect(store.exercises.first { $0.id == legacyBuiltin.id } == expectedLegacy &&
               store.exercises.filter { $0.name == canonicalBench.name }.count == 1,
               "Explicit built-ins still refresh by ID or unambiguous legacy name, keeping existing UUIDs")
        let history = store.records.first { $0.id == record.id }!
        expect(history.exercises.map(\.exerciseID) == record.exercises.map(\.exerciseID) &&
               history.exercises.map(\.id) == record.exercises.map(\.id) &&
               history.exercises.map(\.sets) == record.exercises.map(\.sets) && history.note == record.note &&
               history.exercises[0].muscleMapSnapshot?.primaryGroup == .back &&
               history.exercises[0].muscleMapSnapshot?.secondaryMuscles == custom.secondaryMuscles &&
               history.exercises[1].muscleMapSnapshot == snapshot &&
               history.exercises[2].muscleMapSnapshot?.primaryGroup == .chest,
               "History keeps all IDs/results and existing snapshots; missing snapshots use the correct definition")
        expect(store.records.first { $0.id == template.id }?.exercises[0].exerciseID == custom.id &&
               store.splitPlan.templates[0].exercises[0].exerciseID == custom.id,
               "Workout and split templates keep their links to the custom exercise")
        let loadedRecords = store.records
        for _ in 0..<2 {
            let current = WorkoutStore(fileURL: url)
            expect(current.records == loadedRecords && current.upsert(current.records.first { $0.id == record.id }!),
                   "Repeated save/reload must retain history with the same identities")
            let reloaded = WorkoutStore(fileURL: url)
            expect(reloaded.loadError == nil && reloaded.records == loadedRecords &&
                   reloaded.exercises.first { $0.id == custom.id } == custom &&
                   reloaded.exercises.first { $0.id == other.id } == other &&
                   reloaded.exercises.first { $0.id == builtin.id } == builtin &&
                   reloaded.exercises.filter { $0.name == builtin.name }.count == 2 &&
                   reloaded.splitPlan.templates == split.templates,
                   "Both distinct exercises and all template links survive repeated persistence")
        }
        let editing = WorkoutStore(fileURL: url)
        let definitionCount = editing.exercises.count
        let originalHistory = editing.records
        let legAccent = ExerciseCategory.legs.accents.first!
        let secondary = [MuscleTarget(.back, "Широчайшие")]
        editing.renameExercise(custom, to: custom.name, category: .legs, trackingType: .weightReps,
                               muscleAccent: legAccent, secondaryMuscles: secondary)
        var expectedCustom = custom
        expectedCustom.category = .legs
        expectedCustom.trackingType = .weightReps
        expectedCustom.muscleAccent = legAccent
        expectedCustom.secondaryMuscles = secondary
        expect(editing.saveError == nil && editing.exercises.first { $0.id == custom.id } == expectedCustom &&
               editing.exercises.count == definitionCount && editing.exercises.first { $0.id == builtin.id } == builtin,
               "Editing a custom Pec Deck keeps its UUID/isCustom/image and updates fields despite a built-in name match")
        expect(editing.records == originalHistory && editing.splitPlan.templates == split.templates,
               "A category/type/accent edit must preserve historical results, snapshots and template links")
        let firstEditReload = WorkoutStore(fileURL: url)
        expect(firstEditReload.loadError == nil && firstEditReload.exercises.first { $0.id == custom.id } == expectedCustom &&
               firstEditReload.records == originalHistory,
               "The edited custom definition survives reload without becoming a built-in")

        // An older editor value still identifies the current custom definition by UUID, not its old name/category.
        firstEditReload.renameExercise(custom, to: canonicalBench.name, category: .biceps, trackingType: .reps,
                                       muscleAccent: "Брахиалис", secondaryMuscles: [MuscleTarget(.forearms, "Плечелучевая")])
        let secondEditReload = WorkoutStore(fileURL: url)
        let renamed = secondEditReload.exercises.first { $0.id == custom.id }!
        expect(secondEditReload.loadError == nil && renamed.isCustom && renamed.name == canonicalBench.name &&
               renamed.category == .biceps && renamed.trackingType == .reps && renamed.muscleAccent == "Брахиалис" &&
               renamed.secondaryMuscles == [MuscleTarget(.forearms, "Плечелучевая")] &&
               renamed.illustrationID == custom.illustrationID && secondEditReload.exercises.count == definitionCount &&
               secondEditReload.exercises.first { $0.id == legacyBuiltin.id } == expectedLegacy,
               "Renaming to another built-in name edits only the selected custom UUID and keeps the built-in untouched")
        for oldRecord in originalHistory {
            let updatedRecord = secondEditReload.records.first { $0.id == oldRecord.id }!
            var expectedRecord = oldRecord
            for index in expectedRecord.exercises.indices where expectedRecord.exercises[index].exerciseID == custom.id {
                expectedRecord.exercises[index].name = canonicalBench.name
            }
            expect(updatedRecord == expectedRecord,
                   "Renaming preserves record/set UUIDs, tracking types, results, notes, dates and all historical MuscleMaps")
        }
        expect(secondEditReload.splitPlan.templates == split.templates,
               "Split template IDs, exercise references and saved fields are not rewritten")
        let newWorkout = WorkoutRecord(title: "После изменения категории", exercises: [
            WorkoutExercise(exerciseID: custom.id, name: renamed.name, sets: [SetEntry(repetitions: 12)], trackingType: .reps)
        ])
        expect(secondEditReload.upsert(newWorkout) &&
               secondEditReload.records.first { $0.id == newWorkout.id }?.exercises[0].muscleMapSnapshot?.primaryGroup == .biceps &&
               secondEditReload.records.first { $0.id == record.id }?.exercises[0].muscleMapSnapshot?.primaryGroup == .back,
               "Only new records use the updated MuscleMap; historical snapshots retain their original classification")
        var forgedBuiltin = builtin
        forgedBuiltin.isCustom = true
        let protectedBytes = try! Data(contentsOf: url)
        secondEditReload.renameExercise(forgedBuiltin, to: "Не менять встроенное", category: .back)
        secondEditReload.renameExercise(ExerciseDefinition(name: "Отсутствующий UUID", category: .back), to: "Не создавать")
        expect(secondEditReload.exercises.first { $0.id == builtin.id } == builtin &&
               secondEditReload.exercises.count == definitionCount && (try! Data(contentsOf: url)) == protectedBytes,
               "Stored UUID/isCustom checks protect built-ins and cannot create new definitions from a missing identity")

        var ambiguous = fixture
        var colliding = custom
        colliding.id = builtin.id
        ambiguous.exercises = [colliding]
        let ambiguousBytes = try! JSONEncoder().encode(ambiguous)
        try! ambiguousBytes.write(to: url)
        let blocked = WorkoutStore(fileURL: url)
        expect(blocked.loadError != nil && !blocked.upsert(record) && (try! Data(contentsOf: url)) == ambiguousBytes,
               "A custom/built-in UUID collision is reported and preserved, never automatically reclassified")
        ambiguous.exercises.append(ExerciseDefinition(name: builtin.name, category: builtin.category, isCustom: false))
        let aliasCollisionBytes = try! JSONEncoder().encode(ambiguous)
        try! aliasCollisionBytes.write(to: url)
        let aliasCollision = WorkoutStore(fileURL: url)
        expect(aliasCollision.loadError != nil && !aliasCollision.upsert(record) &&
               (try! Data(contentsOf: url)) == aliasCollisionBytes,
               "A legacy built-in alias must not hide a custom/canonical UUID collision during catalog merging")
        print("PASS: custom/built-in name collisions, full definition preservation, built-in updates, history, templates and repeated reload")
    }

    static func testDuplicateDataProtection() {
        struct Fixture: Encodable {
            var records: [WorkoutRecord]
            var exercises: [ExerciseDefinition]
            var weeklyGoal = 4
            var splitPlan: SplitPlan? = nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("duplicate-data-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let definition = ExerciseDefinition(name: "Тестовая тяга", category: .back, muscleAccent: "Широчайшие")
        let map = MuscleMap(primaryGroup: .back, primaryAccent: "Широчайшие", secondaryMuscles: [MuscleTarget(.biceps, "Бицепс")])
        let calendar = WorkoutStore.statisticsCalendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let first = WorkoutRecord(title: "История", date: date, exercises: [
            WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [SetEntry(weight: 40, repetitions: 8)], muscleMapSnapshot: map)
        ], note: "Не удалять")
        let second = WorkoutRecord(title: "Повторное выполнение", date: date.addingTimeInterval(86_400), exercises: [
            WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [SetEntry(weight: 42.5, repetitions: 8)], muscleMapSnapshot: map)
        ])
        let normal = Fixture(records: [first, second], exercises: [definition])
        let normalData = try! JSONEncoder().encode(normal)
        let url = directory.appendingPathComponent("workouts.json")
        try! normalData.write(to: url)
        let valid = WorkoutStore(fileURL: url)
        let normalAnalysis = MuscleAnalysisEngine.analyze(store: valid, period: .month, relativeTo: now)
        expect(valid.saveError == nil && valid.records == normal.records && normalAnalysis.dataError == nil &&
               normalAnalysis.groups.first { $0.target == MuscleTarget(.back) }?.directSets == 2 &&
               normalAnalysis.groups.first { $0.target == MuscleTarget(.biceps) }?.indirectSets == 2,
               "Normal catalogs and repeated references to one exercise remain valid and keep snapshots")
        expect(InsightsEngine.snapshot(workouts: normal.records, definitions: normal.exercises, now: now).dataError == nil,
               "Normal legacy insights still calculate without errors")
        expect((try! Data(contentsOf: url)) == normalData, "Reading valid history must not rewrite it")

        var conflicting = definition
        conflicting.name = "Другое упражнение"
        conflicting.category = .chest
        var duplicateRecords = normal
        duplicateRecords.records.append(first)
        var duplicateExercises = normal
        duplicateExercises.records[0].exercises.append(first.exercises[0])
        var duplicateSets = normal
        duplicateSets.records[0].exercises[0].sets.append(first.exercises[0].sets[0])
        let splitExercise = SplitTemplateExercise(exerciseID: definition.id, name: definition.name, trackingType: .weightReps)
        let template = SplitWorkoutTemplate(name: "A", exercises: [splitExercise])
        var duplicateSplits = normal
        duplicateSplits.splitPlan = SplitPlan(templates: [template, template])
        var duplicateSplitExercises = normal
        duplicateSplitExercises.splitPlan = SplitPlan(templates: [SplitWorkoutTemplate(name: "A", exercises: [splitExercise, splitExercise])])
        let badFixtures: [(String, Fixture)] = [
            ("same catalog entry", Fixture(records: normal.records, exercises: [definition, definition])),
            ("conflicting catalog entries", Fixture(records: normal.records, exercises: [definition, conflicting])),
            ("duplicate workouts", duplicateRecords), ("duplicate workout exercises", duplicateExercises),
            ("duplicate sets", duplicateSets), ("duplicate split templates", duplicateSplits),
            ("duplicate split exercises", duplicateSplitExercises)
        ]
        for (name, fixture) in badFixtures {
            let bytes = try! JSONEncoder().encode(fixture)
            try! bytes.write(to: url)
            let blocked = WorkoutStore(fileURL: url)
            expect(blocked.loadError?.contains("UUID") == true && blocked.saveError != nil && blocked.records.isEmpty,
                   "An ambiguous state is reported before any records are applied: \(name)")
            expect(Set(blocked.exercises.map(\.id)).count == blocked.exercises.count,
                   "The damaged catalog must never reach SwiftUI or analysis: \(name)")
            let analysis = MuscleAnalysisEngine.analyze(store: blocked, period: .month, relativeTo: now)
            expect(analysis.dataError != nil && analysis.exercises.isEmpty,
                   "Blocked data must not silently become a successful analysis: \(name)")
            expect(!blocked.upsert(first), "No upsert may overwrite ambiguous history: \(name)")
            blocked.weeklyGoal = 6
            expect((try! Data(contentsOf: url)) == bytes, "The original bytes and all UUIDs are preserved: \(name)")
            let reloaded = WorkoutStore(fileURL: url)
            expect(reloaded.loadError != nil && !reloaded.upsert(first) && (try! Data(contentsOf: url)) == bytes,
                   "Restarting cannot overwrite an ambiguous file: \(name)")
        }
        for definitions in [[definition, definition], [definition, conflicting]] {
            let result = InsightsEngine.snapshot(workouts: normal.records, definitions: definitions, now: now)
            expect(result.dataError != nil && result.featured == nil && result.records.isEmpty && result.balance.isEmpty,
                   "Direct insight calls with duplicate UUIDs report failure, rather than selecting an arbitrary definition")
        }
        for fixture in [duplicateRecords, duplicateExercises, duplicateSets] {
            let muscle = MuscleAnalysisEngine.analyze(workouts: fixture.records, muscleMaps: [definition.id: map], period: .month, relativeTo: now)
            let insights = InsightsEngine.snapshot(workouts: fixture.records, definitions: normal.exercises, now: now)
            expect(muscle.dataError != nil && muscle.exercises.isEmpty && insights.dataError != nil && insights.records.isEmpty,
                   "Direct engines must not merge ambiguous workout or set identities")
        }

        var malformed = try! JSONSerialization.jsonObject(with: normalData) as! [String: Any]
        var records = malformed["records"] as! [[String: Any]]
        records[0]["id"] = "not-a-uuid"
        malformed["records"] = records
        let malformedBytes = try! JSONSerialization.data(withJSONObject: malformed)
        try! malformedBytes.write(to: url)
        let damaged = WorkoutStore(fileURL: url)
        expect(damaged.loadError != nil && !damaged.upsert(first) && (try! Data(contentsOf: url)) == malformedBytes,
               "Invalid UUID encoding uses the same load-failure protection without modifying history")

        try! normalData.write(to: url)
        expect(!damaged.upsert(first) && (try! Data(contentsOf: url)) == normalData,
               "A stale blocked store cannot overwrite an externally restored file")
        let restored = WorkoutStore(fileURL: url)
        expect(restored.loadError == nil && restored.records == normal.records,
               "Successful reload restores all original records and UUIDs unchanged")
        expect(!restored.upsert(duplicateSets.records[0]) && restored.records == normal.records &&
               (try! Data(contentsOf: url)) == normalData,
               "New ambiguous set identities are rejected before mutation or saving")
        print("PASS: duplicate catalog/workout/exercise/set/split UUIDs, direct engine errors, malformed IDs and original-file protection")
    }

    static func testNumericInputValidation() {
        func rejects(_ label: String, _ parse: () throws -> Void) {
            do {
                try parse()
                preconditionFailure("Invalid input must be rejected: \(label)")
            } catch { }
        }
        expect(try! SetInputValidation.decimal("60") == 60, "Ordinary weights remain supported")
        expect(try! SetInputValidation.decimal("37.5") == 37.5 && SetInputValidation.decimal("37,5") == 37.5,
               "Both existing decimal separators remain supported")
        expect(try! SetInputValidation.integer("12") == 12 && SetInputValidation.integer("") == 0 &&
               SetInputValidation.decimal("") == 0, "Empty input still clears a numeric value")
        expect(try! SetInputValidation.duration(minutes: "2", seconds: "30") == 150 &&
               SetInputValidation.duration(minutes: "", seconds: "") == 0,
               "Valid durations and cleared fields keep their existing meaning")
        for text in ["inf", "+inf", "-inf", "NaN", "nan", "Infinity", "1e309", "-1", "abc"] {
            rejects(text) { _ = try SetInputValidation.decimal(text) }
        }
        for text in ["inf", "NaN", "-1", "12.5", String(Int.max) + "0"] {
            rejects("repetitions: \(text)") { _ = try SetInputValidation.integer(text) }
        }
        for (minutes, seconds) in [(String(Int.max), "0"), (String(Int.max) + "0", "0"),
                                   ("0", String(Int.max) + "0"), ("0", "60"), ("-1", "0"), ("inf", "0") ] {
            rejects("duration: \(minutes):\(seconds)") {
                _ = try SetInputValidation.duration(minutes: minutes, seconds: seconds)
            }
        }
        expect(try! SetInputValidation.duration(minutes: String(Int.max / 60), seconds: String(Int.max % 60)) == Int.max,
               "The largest representable duration is safe without arbitrary new training limits")
        rejects("duration addition overflow") {
            _ = try SetInputValidation.duration(minutes: String(Int.max / 60), seconds: String(Int.max % 60 + 1))
        }

        // Use exactly the parser called by the row, applying a candidate only after successful validation.
        let originalEntry = SetEntry(weight: 37.5, repetitions: 8, durationSeconds: 150, distanceKilometers: 1.5)
        var entry = originalEntry
        do {
            var candidate = entry
            candidate.weight = try SetInputValidation.decimal("inf")
            entry = candidate
        } catch { }
        expect(entry == originalEntry, "Rejected input must leave the original set and UUID untouched")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("numeric-input-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workouts.json")
        let store = WorkoutStore(fileURL: url)
        let definition = store.exercises[0]
        var record = WorkoutRecord(title: "Проверка ввода", exercises: [
            WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [entry])
        ])
        expect(store.upsert(record), "Normal input can be saved")
        let originalRecords = store.records
        let originalBytes = try! Data(contentsOf: url)
        for value in [Double.infinity, -Double.infinity, Double.nan] {
            for distance in [false, true] {
                var invalid = record
                if distance { invalid.exercises[0].sets[0].distanceKilometers = value }
                else { invalid.exercises[0].sets[0].weight = value }
                expect(!store.upsert(invalid) && store.saveError != nil && store.records == originalRecords,
                       "Non-finite values cannot bypass input validation and enter stored records")
                expect((try! Data(contentsOf: url)) == originalBytes, "Rejected data cannot alter saved history")
            }
        }
        record.exercises[0].sets[0].weight = try! SetInputValidation.decimal("42,5")
        expect(store.upsert(record) && store.saveError == nil, "A valid correction saves normally and clears the error")
        let reloaded = WorkoutStore(fileURL: url)
        expect(reloaded.records == store.records && reloaded.records[0].id == record.id &&
               reloaded.records[0].exercises[0].sets[0].id == originalEntry.id &&
               reloaded.records[0].exercises[0].sets[0].weight == 42.5,
               "Save after rejection survives reload with the same workout and set UUIDs")

        let beforeWriteFailure = store.records
        try! FileManager.default.removeItem(at: url)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        record.note = "Не должно выглядеть сохранённым"
        expect(!store.upsert(record) && store.saveError != nil && store.records == beforeWriteFailure,
               "A write error returns failure and rolls back the unsaved record in memory")
        print("PASS: numeric input, fractions, non-finite values, integer/duration overflow, rejected writes and recovery")
    }

    static func testLoadFailureProtection() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("load-protection-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = directory.appendingPathComponent("valid.json")
        let fresh = WorkoutStore(fileURL: validURL)
        expect(fresh.records.isEmpty && fresh.saveError == nil && !FileManager.default.fileExists(atPath: validURL.path),
               "A genuinely missing file is a normal first launch, not a blocked store")
        let definition = fresh.exercises[0]
        var record = WorkoutRecord(title: "Сохранённая запись", exercises: [
            WorkoutExercise(exerciseID: definition.id, name: definition.name, sets: [SetEntry(weight: 40, repetitions: 8)])
        ])
        record.note = "Заметка, которую нельзя потерять"
        fresh.upsert(record)
        fresh.weeklyGoal = 5
        let expected = fresh.records
        let validData = try! Data(contentsOf: validURL)
        let valid = WorkoutStore(fileURL: validURL)
        expect(valid.saveError == nil && valid.records == expected && valid.weeklyGoal == 5,
               "A valid store loads its records, UUIDs, snapshots, notes and settings")
        expect(try! Data(contentsOf: validURL) == validData, "Loading a valid file must not rewrite it through weeklyGoal.didSet")

        for (name, original) in [("empty", Data()), ("corrupt", Data("{broken".utf8)), ("wrong-schema", Data("[]".utf8))] {
            let url = directory.appendingPathComponent(name + ".json")
            try! original.write(to: url)
            let blocked = WorkoutStore(fileURL: url)
            guard let error = blocked.saveError else { preconditionFailure("Existing unreadable data must block writes: \(name)") }
            let catalog = blocked.exercises
            let goal = blocked.weeklyGoal
            blocked.upsert(record)
            blocked.delete(record)
            blocked.moveExercise(UUID(), to: UUID(), in: record.id)
            blocked.addExercise(named: "Не должно сохраниться", category: .chest)
            blocked.renameExercise(definition, to: "Другое имя")
            blocked.deleteExercise(definition)
            blocked.setSplitEnabled(true)
            blocked.upsertSplitTemplate(SplitWorkoutTemplate(name: "Не должен сохраниться", exercises: []))
            blocked.deleteSplitTemplates(at: IndexSet(integer: 0))
            blocked.moveSplitTemplates(from: IndexSet(integer: 0), to: 1)
            blocked.skipNextSplitTemplate(on: .now)
            blocked.completeSplitWorkout(record.id)
            expect(blocked.prepareNextSplitWorkout(on: .now) == nil, "A failed load cannot create a split draft")
            blocked.weeklyGoal = 7
            expect(blocked.records.isEmpty && blocked.exercises == catalog && blocked.weeklyGoal == goal &&
                   !blocked.splitPlan.isEnabled && blocked.splitPlan.templates.isEmpty,
                   "Blocked mutations must not create the appearance of saved workouts, catalog, splits or settings")
            expect(blocked.saveError == error && (try! Data(contentsOf: url)) == original,
                   "Every write path preserves the exact original bytes and persistent load error: \(name)")
            let stillBlocked = WorkoutStore(fileURL: url)
            stillBlocked.upsert(record)
            expect(stillBlocked.saveError != nil && (try! Data(contentsOf: url)) == original,
                   "Restarting against the same damaged file cannot silently unblock writes")

            try! FileManager.default.removeItem(at: url)
            blocked.upsert(record)
            expect(!FileManager.default.fileExists(atPath: url.path) && blocked.saveError == error,
                   "Removing the file after a failed load does not turn the stale store into a fresh installation")
            try! validData.write(to: url)
            blocked.upsert(record)
            expect((try! Data(contentsOf: url)) == validData && blocked.saveError == error,
                   "The old empty state must not overwrite a restored valid file")
            let recovered = WorkoutStore(fileURL: url)
            expect(recovered.saveError == nil && recovered.records == expected && recovered.weeklyGoal == 5,
                   "A new store may resume only after the restored file loads successfully")
            var edited = recovered.records[0]
            edited.note = "Правка после успешной загрузки"
            recovered.upsert(edited)
            expect(recovered.saveError == nil && WorkoutStore(fileURL: url).records.first?.note == edited.note,
                   "Successful recovery supports normal persistence again")
        }

        let danglingURL = directory.appendingPathComponent("dangling.json")
        let missingTarget = directory.appendingPathComponent("absent-target.json")
        try! FileManager.default.createSymbolicLink(at: danglingURL, withDestinationURL: missingTarget)
        let dangling = WorkoutStore(fileURL: danglingURL)
        expect(dangling.saveError != nil, "An existing dangling symlink is not a first launch")
        dangling.upsert(record)
        expect((try! FileManager.default.destinationOfSymbolicLink(atPath: danglingURL.path)) == missingTarget.path,
               "A failed read must not replace an existing symlink")

        let directoryURL = directory.appendingPathComponent("directory.json", isDirectory: true)
        try! FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let wrongType = WorkoutStore(fileURL: directoryURL)
        wrongType.upsert(record)
        expect(wrongType.saveError != nil && wrongType.records.isEmpty &&
               (try! FileManager.default.attributesOfItem(atPath: directoryURL.path)[.type] as! FileAttributeType) == .typeDirectory,
               "Existing paths that cannot be read as files stay untouched")

        // A later disk write failure must also remain visible, without reporting success.
        try! FileManager.default.removeItem(at: validURL)
        try! FileManager.default.createDirectory(at: validURL, withIntermediateDirectories: true)
        valid.upsert(record)
        expect(valid.saveError != nil, "Disk write failures must not clear saveError")
        print("PASS: first launch, valid reload, corrupt/empty/schema/read errors, all blocked mutations, restored-file reload and write errors")
    }

    static func testPersonalStoreStartup() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("personal-startup-\(UUID().uuidString).json")
        let store = WorkoutStore(fileURL: file)
        let now = WorkoutStore.statisticsCalendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        expect(store.records.isEmpty && store.workouts.isEmpty && store.templates.isEmpty,
               "First startup must not create workouts or templates")
        for period in StatsPeriod.allCases {
            let analysis = MuscleAnalysisEngine.analyze(store: store, period: period, relativeTo: now)
            let insights = InsightsEngine.personalInsights(from: analysis)
            expect(analysis.readiness == .collecting && analysis.exercises.isEmpty &&
                   analysis.groups.allSatisfy { $0.directSets == 0 && $0.indirectSets == 0 } &&
                   insights.insights.isEmpty && RecommendationEngine.recommendations(analysis: analysis, insights: insights).isEmpty,
                   "Empty history keeps collecting state without fake observations for \(period.rawValue)")
            expect(store.snapshot(for: period, relativeTo: now).workoutCount == 0,
                   "Empty statistics do not include synthetic activity")
        }
        expect(!FileManager.default.fileExists(atPath: file.path), "Reading empty history must not create a data file")
        let exercise = store.exercises[0]
        store.upsert(WorkoutRecord(title: "Проверка сохранения", date: now, exercises: [
            WorkoutExercise(exerciseID: exercise.id, name: exercise.name, sets: [SetEntry(weight: 40, repetitions: 8)])
        ]))
        store.upsert(WorkoutRecord(title: "Шаблон", exercises: [
            WorkoutExercise(exerciseID: exercise.id, name: exercise.name)
        ], isTemplate: true))
        store.weeklyGoal = 4
        let expected = store.records
        let data = try! Data(contentsOf: file)
        // Even an ephemeral store explicitly pointed at the same file cannot read or overwrite it.
        let isolated = WorkoutStore(fileURL: file, isEphemeral: true)
        expect(isolated.records.isEmpty, "An isolated store does not read personal history")
        isolated.upsert(WorkoutRecord(title: "Изолированная проверка"))
        expect(try! Data(contentsOf: file) == data, "Ephemeral activity cannot overwrite personal storage")
        let reloaded = WorkoutStore(fileURL: file)
        expect(reloaded.records == expected && reloaded.weeklyGoal == 4 && reloaded.templates.count == 1,
               "Restart preserves workout, template, set UUIDs, muscle snapshots and settings exactly")
        expect(try! Data(contentsOf: file) == data, "Reload must not rewrite the stored history")
        print("PASS: empty startup, no synthetic insights, isolated data, personal history and settings survive reload")
    }

    static func testChartSelection() {
        expect(ChartPointSelection.nearestIndex(to: 10, positions: []) == nil, "Empty plots have no selection")
        expect(ChartPointSelection.nearestIndex(to: -100, positions: [40]) == 0 &&
               ChartPointSelection.nearestIndex(to: 200, positions: [40]) == 0, "A single point stays selectable")
        expect(ChartPointSelection.nearestIndex(to: -10, positions: [0, 10, 100]) == 0 &&
               ChartPointSelection.nearestIndex(to: 200, positions: [0, 10, 100]) == 2,
               "Selection clamps to real endpoints")
        expect(ChartPointSelection.nearestIndex(to: 45, positions: [0, 10, 100]) == 1 &&
               ChartPointSelection.nearestIndex(to: 70, positions: [0, 10, 100]) == 2,
               "Snap uses actual horizontal spacing, not interpolated or evenly spaced dates")
        expect(ChartPointSelection.nearestIndex(to: 5, positions: [0, 10]) == 0 &&
               ChartPointSelection.nearestIndex(to: 10, positions: [10, 10, 30]) == 0,
               "Equal-distance and same-date ties choose the first real observation deterministically")
        expect(ChartPointSelection.nearestIndex(to: .nan, positions: [1]) == nil &&
               ChartPointSelection.nearestIndex(to: 10, positions: [.nan, 11, .infinity]) == 1,
               "Invalid pointer or plot coordinates cannot create synthetic values")

        let calendar = WorkoutStore.statisticsCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let store = WorkoutStore(isEphemeral: true)
        let press = store.exercises.first { $0.name == "Жим штанги лёжа" }!
        let run = store.exercises.first { $0.name == "Бег" }!
        for day in 1...6 {
            let date = calendar.date(byAdding: .day, value: day - 10, to: now)!
            let weight = Double(50 + day)
            let sets = [SetEntry(weight: 20, repetitions: 10), SetEntry(weight: 30, repetitions: 7),
                        SetEntry(weight: weight, repetitions: 8), SetEntry(weight: weight, repetitions: 8)]
            store.upsert(WorkoutRecord(title: "Изолированная проверка графика", date: date, exercises: [
                WorkoutExercise(exerciseID: press.id, name: press.name, sets: sets),
                // Multiple instances in one workout still produce one maximum per metric.
                WorkoutExercise(exerciseID: press.id, name: press.name, sets: [SetEntry(weight: 10, repetitions: 2)]),
                WorkoutExercise(exerciseID: run.id, name: run.name,
                                sets: [SetEntry(durationSeconds: 1200 + day, distanceKilometers: Double(day))], trackingType: .cardio)
            ]))
        }
        let report = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: now)
        let strength = report.exercises.first { $0.exerciseID == press.id }!
        expect(strength.recentObservations.count == 5 && strength.observationCount == 6 &&
               strength.recentObservations.map(\.value) == strength.recentValues,
               "Displayed points are exactly the five real observations used for the trend")
        for point in strength.recentObservations {
            let workout = store.records.first { $0.id == point.id }!
            let source = point.sourceSet!
            expect(point.date == workout.date && workout.exercises.flatMap(\.sets).contains(source),
                   "The readout keeps the actual date, workout identity and recorded source set")
            expect(abs(point.value - source.weight * (1 + Double(source.repetitions) / 30)) < 0.000001 && source.weight > 30,
                   "Strength readout agrees with existing calculation and excludes inferred warmups")
        }
        let cardio = report.exercises.filter { $0.exerciseID == run.id }
        expect(cardio.count == 2 && cardio.allSatisfy { item in
            item.recentObservations.allSatisfy { point in
                item.metric == .cardioDistanceKilometers
                    ? point.value == point.sourceSet?.distanceKilometers
                    : point.value == Double(point.sourceSet!.durationSeconds)
            }
        }, "Duration and distance use separate metrics and actual source values")
        for period in StatsPeriod.allCases {
            let snapshot = store.snapshot(for: period, relativeTo: now)
            expect(snapshot.buckets.allSatisfy { bucket in
                guard let interval = bucket.period else { return false }
                let count = snapshot.workouts.filter { $0.date >= interval.start && $0.date < interval.end }.count
                return count == bucket.count
            }, "Bar readout intervals match the actual aggregation for \(period.rawValue)")
        }
        let empty = MuscleAnalysisEngine.analyze(store: WorkoutStore(isEphemeral: true), period: .month, relativeTo: now)
        expect(empty.exercises.isEmpty, "No placeholder observations may be generated")
        print("PASS: chart snap, boundaries, real source values, warmups, aggregation, cardio units and bucket dates")
    }

    static func testExerciseOrdering() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("exercise-order-tests-\(UUID().uuidString).json")
        let store = WorkoutStore(fileURL: file)
        let definitions = Array(ExerciseDefinition.builtIn.prefix(3))
        let exercises = definitions.enumerated().map { index, definition in
            WorkoutExercise(exerciseID: definition.id, name: definition.name,
                            sets: [SetEntry(weight: Double(30 + index * 10), repetitions: 8)],
                            trackingType: definition.trackingType)
        }
        let record = WorkoutRecord(title: "Порядок", exercises: exercises)
        store.upsert(record)
        let original = store.records.first { $0.id == record.id }!
        let ids = original.exercises.map(\.id)
        store.moveExercise(ids[0], to: ids[2], in: record.id)
        expect(store.records.first { $0.id == record.id }!.exercises.map(\.id) == [ids[1], ids[2], ids[0]],
               "Dragging down moves the entire exercise after its destination")
        store.moveExercise(ids[0], to: ids[1], in: record.id)
        expect(store.records.first { $0.id == record.id }!.exercises == original.exercises,
               "Dragging back up restores the exact exercise values, sets and snapshots")
        store.moveExercise(ids[2], to: ids[0], in: record.id)
        let moved = store.records.first { $0.id == record.id }!
        expect(moved.exercises.map(\.id) == [ids[2], ids[0], ids[1]], "Last exercise can become first")
        store.moveExercise(ids[2], to: ids[2], in: record.id)
        store.moveExercise(UUID(), to: ids[0], in: record.id)
        store.moveExercise(ids[0], to: UUID(), in: record.id)
        store.moveExercise(ids[0], to: ids[1], in: UUID())
        expect(store.records.first { $0.id == record.id } == moved, "Invalid and self drops cannot mutate a workout")
        let reloaded = WorkoutStore(fileURL: file)
        expect(reloaded.workouts.first { $0.id == record.id }?.exercises == moved.exercises,
               "Persisted order and all exercise data survive reload and feed history unchanged")

        var template = moved
        template.id = UUID()
        template.isTemplate = true
        store.upsert(template)
        template.moveExercise(ids[1], to: ids[2])
        store.upsert(template)
        let savedTemplate = WorkoutStore(fileURL: file).templates.first { $0.id == template.id }!
        expect(savedTemplate.exercises == template.exercises, "Creating and updating a template preserve the chosen order")
        var loadedWorkout = savedTemplate
        loadedWorkout.id = UUID()
        loadedWorkout.isTemplate = false
        store.upsert(loadedWorkout)
        expect(store.workouts.first { $0.id == loadedWorkout.id }?.exercises == savedTemplate.exercises,
               "Loading an existing workout template preserves its exercise order")
        let split = SplitWorkoutTemplate(name: "Порядок", exercises: savedTemplate.exercises.map {
            SplitTemplateExercise(exerciseID: $0.exerciseID, name: $0.name, trackingType: $0.trackingType)
        })
        store.upsertSplitTemplate(split)
        store.setSplitEnabled(true)
        expect(store.prepareNextSplitWorkout(on: .now)?.exercises.map(\.exerciseID) == savedTemplate.exercises.map(\.exerciseID),
               "Split template loading must also preserve its stored order")
        expect(store.records.first { $0.id == record.id } == moved, "Template actions do not change the original workout")
        print("PASS: exercise moves up/down, invalid drops, persistence, history and template order")
    }

    static func testRepetitionRecords() {
        let definition = ExerciseDefinition.builtIn.first { $0.name == "Жим штанги лёжа" }!
        let calendar = WorkoutStore.statisticsCalendar
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        func workout(_ offset: Int, _ values: [(Double, Int)], id: UUID? = nil) -> WorkoutRecord {
            WorkoutRecord(title: "Проверка", date: calendar.date(byAdding: .day, value: offset, to: day)!,
                          exercises: [WorkoutExercise(exerciseID: id ?? definition.id, name: definition.name,
                                                      sets: values.map { SetEntry(weight: $0.0, repetitions: $0.1) })])
        }
        func records(_ history: [WorkoutRecord]) -> [ExerciseRecord] {
            InsightsEngine.snapshot(workouts: history, definitions: [definition],
                                    now: calendar.date(byAdding: .day, value: 25, to: day)!).records
        }
        func repetitions(_ history: [WorkoutRecord]) -> ExerciseRecord? {
            records(history).first { $0.id == "reps-\(definition.id)" }
        }
        let earlier = workout(0, [(20, 12), (30, 8)])
        let improved = workout(10, [(20, 10), (30, 9)])
        expect(repetitions([earlier, improved])?.result == "30 кг × 9",
               "A same-weight improvement must not be hidden by more repetitions with another weight")
        expect(repetitions([improved, earlier])?.result == "30 кг × 9",
               "Repetition records must follow workout dates rather than input ordering")
        let sameWeight = [workout(0, [(30, 10)]), workout(10, [(30, 12)])]
        expect(repetitions(sameWeight)?.result == "30 кг × 12", "Repetitions improve at exactly the same weight")
        expect(repetitions([workout(0, [(30, 10)]), workout(10, [(30, 10)])]) == nil,
               "Identical results are not new repetition records")
        expect(repetitions([workout(0, [(30, 10)]), workout(10, [(30, 9)])]) == nil,
               "Fewer repetitions cannot create a repetition record")
        expect(repetitions([workout(0, [(20, 10)]), workout(10, [(30, 12)])]) == nil,
               "Different weights cannot serve as repetition baselines for each other")
        expect(repetitions([workout(0, [(30, 8)]), workout(10, [(20, 10), (20, 12)])]) == nil,
               "Two sets in one workout are not two comparable performances")
        expect(repetitions([workout(0, [(30, 10)]), workout(10, [(30, 12)], id: UUID())]) == nil,
               "Different exercise IDs must not share repetition records")
        expect(repetitions(sameWeight + [workout(20, [(30, 11)])])?.date == sameWeight[1].date,
               "A later lower result must preserve an earlier confirmed improvement")
        let result = records([earlier, improved])
        expect(result.first { $0.id == "strength-\(definition.id)" }?.result == "30 кг × 9" &&
               result.first { $0.id == "weight-\(definition.id)" }?.result == "30 кг × 8",
               "Strength and maximum-weight selection must keep their existing rules")

        // Known ambiguity: the stored model cannot prove that an earlier light set was working.
        let baseline = workout(0, [(20, 10)])
        let before = workout(10, [(20, 12), (25, 10), (30, 8)])
        let after = workout(10, [(20, 12), (25, 10), (30, 8), (30, 8)])
        print("LIMITATION: ambiguous 20 kg record before/after second heavy set: \(repetitions([baseline, before])?.result ?? "none") / \(repetitions([baseline, after])?.result ?? "none")")
        print("PASS: repetition improvements are compared within weight and exercise, without changing strength records")
    }

    static func testWarmupClassification() {
        func sets(_ values: [(Double, Int)]) -> [SetEntry] {
            values.map { SetEntry(weight: $0.0, repetitions: $0.1) }
        }
        func retained(_ values: [(Double, Int)], type: ExerciseTrackingType = .weightReps) -> [Int] {
            let entries = sets(values)
            let ids = Set(WorkoutSetClassifier.workingSets(entries, type: type).map(\.id))
            return entries.indices.filter { ids.contains(entries[$0].id) }
        }
        let bench: [(Double, Int)] = [(20, 10), (30, 7), (40, 7), (50, 7), (60, 4), (60, 4), (60, 4)]
        expect(retained(bench) == [3, 4, 5, 6], "Only clearly light preparation is excluded; 50 kg remains ambiguous")
        expect(retained([(45, 7), (45, 8), (45, 8)]) == [0, 1, 2], "Butterfly sets all remain working")
        expect(retained([(60, 4), (60, 4), (60, 4)]) == [0, 1, 2], "Equal working weights stay eligible")
        expect(retained(bench + [(40, 8), (30, 10)]) == [3, 4, 5, 6, 7, 8], "Lighter back-off sets must survive")
        expect(retained([(0, 10), (0, 8)], type: .reps) == [0, 1], "Bodyweight exercise sets are never inferred as warmups")
        expect(retained([(20, 10), (60, 4)]) == [0, 1], "A single heavier set is insufficient evidence")
        expect(retained([(30, 8), (20, 10), (60, 4), (60, 4)]) == [0, 1, 2, 3], "A mixed prefix is ambiguous")
        expect(retained([(20, 30), (40, 7), (60, 4), (60, 4)]) == [0, 2, 3], "High-rep effort must not be called light based on weight alone")
        expect(retained(bench, type: .duration).count == bench.count &&
               retained(bench, type: .cardio).count == bench.count, "Time and cardio are unchanged")

        let definition = ExerciseDefinition.builtIn.first { $0.name == "Жим штанги лёжа" }!
        let map = MuscleMap(primaryGroup: .chest, primaryAccent: "Средняя часть груди",
                            secondaryMuscles: definition.secondaryMuscles)
        let exercise = WorkoutExercise(exerciseID: definition.id, name: definition.name,
                                       sets: sets(bench), muscleMapSnapshot: map)
        let calendar = WorkoutStore.statisticsCalendar
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let record = WorkoutRecord(title: "История", date: day, exercises: [exercise])
        let restored = try! JSONDecoder().decode(WorkoutRecord.self, from: JSONEncoder().encode(record))
        expect(restored.id == record.id && restored.exercises[0] == exercise,
               "Classification must not alter stored sets, IDs or muscle snapshots")
        expect(restored.exercises[0].analysisSets.map(\.id) == Array(exercise.sets[3...]).map(\.id),
               "Existing records are classified dynamically after decoding")
        let store = WorkoutStore(isEphemeral: true)
        store.upsert(restored)
        let analysis = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: day)
        expect(analysis.groups.first { $0.target == MuscleTarget(.chest) }?.directSets == 4 &&
               analysis.groups.first { $0.target == MuscleTarget(.triceps) }?.indirectSets == 4,
               "Direct and indirect muscle counts use the same working sets")
        expect(abs((analysis.exercises.first?.latest ?? 0) - 68) < 0.001,
               "Strength uses the best eligible effort, not set count")
        expect(analysis.regularity.workoutCount == 1 && store.snapshot(for: .month, relativeTo: day).totalVolume == 1760,
               "Regularity and total recorded tonnage must not change")
        expect(store.records[0].exercises[0].sets.count == 7, "Raw history keeps all seven sets")
        print("PASS: conservative warmup classification, back-off sets and historical data")
    }

    static func testExerciseTrends() {
        let trend = MuscleAnalysisEngine.trend
        expect(trend([100, 102, 104, 106, 108], .estimatedOneRepMax) == .improvement,
               "Gradual improvement needs five comparable results")
        expect(trend([100, 104, 102, 106, 109], .estimatedOneRepMax) == .improvement,
               "A small fluctuation must not hide a sustained rise")
        expect(trend([100, 101, 99, 100, 101], .estimatedOneRepMax) == .stable,
               "Small changes around one level are stable")
        expect(trend([110, 108, 105, 103, 100], .estimatedOneRepMax) == .decline,
               "A sustained decrease is descriptive, not a fitness diagnosis")
        expect(trend([100, 102, 104, 106], .estimatedOneRepMax) == .insufficientData,
               "Four results must not create a confirmed trend")
        expect(trend([100, 107, 95, 106, 100], .estimatedOneRepMax) == .changed,
               "Strongly mixed results must remain uncertain")
        expect(trend([20, 22, 24, 26, 28], .cardioDistanceKilometers) == .changed,
               "More cardio distance alone must not mean improved fitness")
    }

    static func testInsightWording() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let period = DateInterval(start: end.addingTimeInterval(-12 * 86_400), end: end)
        let trendPeriod = DateInterval(start: end.addingTimeInterval(-4 * 86_400), end: end)
        let previous = DateInterval(start: end.addingTimeInterval(-24 * 86_400), end: period.start)
        let exerciseID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
        func snapshot(_ values: [Double], record: Bool = false) -> MuscleAnalysisSnapshot {
            let exercise = ExerciseProgressResult(
                exerciseID: exerciseID, name: "Тяга верхнего блока", metric: .estimatedOneRepMax,
                latest: values.last, previous: values.dropLast().last, observationCount: 10,
                canCompare: true, canInferTrend: true,
                trend: MuscleAnalysisEngine.trend(for: values, metric: .estimatedOneRepMax),
                isPersonalRecord: record, currentPeriodChange: nil, previousPeriodChange: nil,
                observationPeriod: DateInterval(start: previous.start, end: end),
                trendPeriod: trendPeriod, recentValues: values)
            let regularity = MuscleRegularityResult(workoutCount: 5, activeWeekCount: 2,
                weeklyFrequency: [], previousWorkoutCount: 0, previousActiveWeekCount: 0,
                observationCount: 5, canComparePeriods: false, consecutiveActiveWeeks: 0,
                inactiveWeeksBeforeReturn: nil, streakPeriod: nil, returnPeriod: nil)
            let cardio = MuscleCardioResult(sessionCount: 0, durationSeconds: 0, distanceKilometers: 0,
                distanceObservationCount: 0, previousSessionCount: 0, previousDurationSeconds: 0,
                previousDistanceKilometers: 0, previousDistanceObservationCount: 0,
                observationCount: 0, canComparePeriods: false)
            return MuscleAnalysisSnapshot(period: period, previousPeriod: previous, readiness: .preliminary,
                historyAgeDays: 33, observationCount: 5, groups: [], accents: [],
                exercises: [exercise], regularity: regularity, cardio: cardio)
        }
        func recommendation(_ analysis: MuscleAnalysisSnapshot) -> TrainingRecommendation? {
            RecommendationEngine.recommendations(analysis: analysis,
                insights: PersonalInsightsResult(readiness: .preliminary, observationCount: 5, insights: [])).first
        }

        let identical = snapshot([50, 50, 50, 50, 50])
        let close = snapshot([50, 51, 50, 50, 51])
        expect(identical.exercises[0].trend == .stable && close.exercises[0].trend == .stable,
               "Both identical and close values may be stable")
        expect(recommendation(identical) == nil && recommendation(close) == nil,
               "Stable results alone must not create a recommendation")
        let stableInsight = InsightsEngine.personalInsights(from: close).insights.first
        expect(stableInsight?.explanation.contains("небольшими колебаниями") == true &&
               stableInsight?.period == trendPeriod,
               "Stable insight and recommendation must describe the same five results")
        expect(RecommendationEngine.recommendations(analysis: close,
            insights: InsightsEngine.personalInsights(from: close)).isEmpty,
            "Recommendation must not duplicate an already shown insight")

        let rising = snapshot([60, 62, 61, 64, 63])
        expect(rising.exercises[0].trend == .improvement &&
               recommendation(rising)?.explanation.contains("в целом вырос") == true &&
               recommendation(rising)?.observationCount == 5 &&
               recommendation(rising)?.period == trendPeriod,
               "An improving but fluctuating series must not be described as monotonic")
        expect(RecommendationEngine.recommendations(analysis: rising,
            insights: InsightsEngine.personalInsights(from: rising)).isEmpty,
            "A visible progress insight must not be repeated as a recommendation")
        let mixed = snapshot([45, 50, 42, 51, 46])
        expect(mixed.exercises[0].trend == .changed && recommendation(mixed) == nil &&
               InsightsEngine.personalInsights(from: mixed).insights.isEmpty,
               "Ambiguous results must not produce a confirmed progress claim")
        let falling = snapshot([70, 68, 69, 66, 65])
        expect(falling.exercises[0].trend == .decline &&
               InsightsEngine.personalInsights(from: falling).insights.first?.explanation.contains("причина неизвестна") == true,
               "A decline must be descriptive, not a fitness diagnosis")
        let record = snapshot([60, 62, 64, 66, 68], record: true)
        expect(InsightsEngine.personalInsights(from: record).insights.first?.explanation.localizedCaseInsensitiveContains("оценка силы") == true &&
               recommendation(record) == nil,
               "Record wording must name the comparable metric and not duplicate a progress recommendation")
        print("PASS: insight and recommendation wording for identical, close, rising, mixed, falling and record results")
    }

    static func testHistoricalMuscleMaps() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("muscle-map-tests-\(UUID().uuidString).json")
        let store = WorkoutStore(fileURL: file)
        store.addExercise(named: "Историческая тяга", category: .back, muscleAccent: "Широчайшие",
                          secondaryMuscles: [MuscleTarget(.biceps, "Бицепс")])
        let definition = store.exercises.first { $0.name == "Историческая тяга" }!
        let calendar = Calendar(identifier: .iso8601)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let analysisDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let item = WorkoutExercise(exerciseID: definition.id, name: definition.name,
                                   sets: [SetEntry(weight: 30, repetitions: 8)])
        let record = WorkoutRecord(title: "История", date: date, exercises: [item])
        store.upsert(record)
        let original = store.records.first { $0.id == record.id }!.exercises[0]
        expect(original.id == item.id && original.sets == item.sets &&
               original.muscleMapSnapshot?.primaryGroup == .back &&
               original.muscleMapSnapshot?.primaryAccent == "Широчайшие" &&
               original.muscleMapSnapshot?.secondaryMuscles == [MuscleTarget(.biceps, "Бицепс")],
               "Saving must capture the muscle map without changing IDs or results")

        store.renameExercise(definition, to: "Историческая тяга", category: .chest,
                             muscleAccent: "Верх груди")
        store.upsert(record) // An editor can still hold the older, snapshot-free value.
        let afterEdit = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: analysisDate)
        expect(afterEdit.groups.first { $0.target == MuscleTarget(.back) }?.directSets == 1 &&
               afterEdit.groups.first { $0.target == MuscleTarget(.biceps) }?.indirectSets == 1 &&
               afterEdit.groups.first { $0.target == MuscleTarget(.chest) }?.directSets == 0,
               "Editing a definition must not reclassify a recorded workout")

        store.deleteExercise(store.exercises.first { $0.id == definition.id }!)
        let afterDelete = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: analysisDate)
        expect(afterDelete.groups.first { $0.target == MuscleTarget(.back) }?.directSets == 1,
               "Deleting a definition must not remove historical muscle activity")
        let reloaded = WorkoutStore(fileURL: file)
        expect(reloaded.records.first { $0.id == record.id }?.exercises[0].muscleMapSnapshot == original.muscleMapSnapshot &&
               reloaded.records.first { $0.id == record.id }?.exercises[0].id == item.id,
               "The snapshot and workout UUID must survive reload")

        let legacyFile = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-muscle-map-tests-\(UUID().uuidString).json")
        let legacy = WorkoutStore(fileURL: legacyFile)
        let standard = ExerciseDefinition.builtIn.first { $0.name == "Подтягивания" }!
        legacy.upsert(WorkoutRecord(title: "Старая запись", date: date,
                                    exercises: [WorkoutExercise(exerciseID: standard.id, name: standard.name,
                                                                sets: [SetEntry(repetitions: 6)], trackingType: .reps)]))
        let data = try! Data(contentsOf: legacyFile)
        var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        var records = json["records"] as! [[String: Any]]
        var exercises = records[0]["exercises"] as! [[String: Any]]
        exercises[0].removeValue(forKey: "muscleMapSnapshot")
        var unknown = records[0]
        unknown["id"] = UUID().uuidString
        var unknownExercise = exercises[0]
        unknownExercise["id"] = UUID().uuidString
        unknownExercise["exerciseID"] = UUID().uuidString
        unknownExercise["name"] = "Удалённое упражнение"
        unknown["exercises"] = [unknownExercise]
        records[0]["exercises"] = exercises
        records.append(unknown)
        json["records"] = records
        try! JSONSerialization.data(withJSONObject: json).write(to: legacyFile)
        let restored = WorkoutStore(fileURL: legacyFile)
        expect(restored.records[0].exercises[0].muscleMapSnapshot?.primaryGroup == .back,
               "A legacy record should use an available exercise definition")
        expect(restored.records.count == 2 && restored.workouts.count == 2 &&
               restored.records[1].exercises[0].sets == legacy.records[0].exercises[0].sets &&
               restored.records[1].exercises[0].muscleMapSnapshot == nil,
               "A legacy record without a definition must survive without invented classification")
        expect(MuscleAnalysisEngine.analyze(store: restored, period: .month, relativeTo: analysisDate)
            .groups.first { $0.target == MuscleTarget(.back) }?.directSets == 1,
               "Only the classifiable legacy activity belongs in muscle analysis")
        print("PASS: historical muscle maps, edit, delete, reload and legacy JSON")
    }

    static func testBuiltInMuscleMaps() {
        let builtIn = ExerciseDefinition.builtIn
        let retiredFile = FileManager.default.temporaryDirectory.appendingPathComponent("retired-catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: retiredFile) }
        let retiredStore = WorkoutStore(fileURL: retiredFile)
        for name in ["Пуловер в тренажёре", "Сгибание рук в тренажёре",
                     "Жим от груди в тренажёре", "Жим на плечи в тренажёре"] {
            let archived = ExerciseDefinition.historicalBuiltIn.first { $0.name == name }!
            expect(!builtIn.contains { $0.id == archived.id } && !archived.matchesSearch(name) &&
                   archived.searchAliases.isEmpty, "Retired exercises must not be available in catalog/search")
            let item = WorkoutExercise(exerciseID: archived.id, name: name,
                                       sets: [SetEntry(weight: 30, repetitions: 8)])
            var record = WorkoutRecord(title: "Historical record", exercises: [item])
            expect(retiredStore.upsert(record), "Historical retired exercise must remain saveable")
            record.id = UUID()
            record.isTemplate = true
            expect(retiredStore.upsert(record), "Templates keep retired exercise references")
        }
        let retiredReload = WorkoutStore(fileURL: retiredFile)
        expect(retiredReload.records == retiredStore.records && retiredReload.records.count == 8 &&
               retiredReload.records.allSatisfy { $0.exercises.first?.muscleMapSnapshot != nil },
               "Retired exercise UUIDs, records, templates and maps survive reload")
        let customRetiredName = ExerciseDefinition(name: "Сгибание рук в тренажёре", category: .back)
        expect(customRetiredName.isAvailableInLibrary && customRetiredName.matchesSearch("Сгибание рук"),
               "Retiring built-ins must not hide custom exercises with matching names")
        expect(Set(builtIn.map(\.id)).count == builtIn.count, "Built-in UUIDs must remain unique")
        let pecDeck = builtIn.first { $0.name == "Бабочка" }!
        expect(builtIn.filter { $0.matchesSearch("бабочка") }.map(\.id) == [pecDeck.id] &&
               pecDeck.matchesSearch("  СВЕДЕНИЕ РУК  "), "Pec Deck must be searchable by both Russian names without duplicates")
        expect(pecDeck.id == UUID(uuidString: "00000000-0000-4000-8000-00000000002E") &&
               pecDeck.category == .chest && pecDeck.muscleAccent == "Средняя часть груди" &&
               pecDeck.trackingType == .weightReps && pecDeck.secondaryMuscles.isEmpty,
               "Pec Deck uses a new fixed ID, weight/reps and isolated chest classification")
        expect(builtIn.first { $0.name == "Сведение рук в кроссовере" }?.id ==
               UUID(uuidString: "00000000-0000-4000-8000-000000000004"), "Cable crossover keeps its original identity")
        for exercise in builtIn {
            expect(exercise.category == .cardio || exercise.category.accents.contains(exercise.muscleAccent ?? ""),
                   "Every strength exercise needs a valid primary accent: \(exercise.name)")
            expect(Set(exercise.secondaryMuscles).count == exercise.secondaryMuscles.count &&
                   exercise.secondaryMuscles.allSatisfy { $0.category != .cardio && $0.category.accents.contains($0.accent ?? "") },
                   "Secondary accents must be valid and unique: \(exercise.name)")
            if exercise.category == .cardio {
                expect(exercise.trackingType == .cardio && exercise.secondaryMuscles.isEmpty,
                       "Cardio must not receive strength muscle targets: \(exercise.name)")
            }
        }
        func definition(_ name: String) -> ExerciseDefinition {
            ExerciseDefinition.historicalBuiltIn.first { $0.name == name }!
        }
        func targets(_ name: String) -> Set<MuscleTarget> {
            Set(definition(name).secondaryMuscles)
        }
        let machineQueries = ["Pec Deck", "Тяга верхнего блока", "Горизонтальная тяга блока",
                              "Жим ногами", "Разгибание ног", "Сгибание ног",
                              "Разгибание рук на верхнем блоке"]
        for query in machineQueries {
            expect(builtIn.filter { $0.matchesSearch(query) }.count == 1,
                   "Every requested machine exercise or synonym must resolve once: \(query)")
        }
        for (oldName, newName) in [
            ("Бабочка (сведение рук в тренажёре)", "Бабочка")
        ] {
            expect(builtIn.filter { $0.matchesSearch(oldName) }.map(\.id) == [definition(newName).id] &&
                   builtIn.filter { $0.name == oldName }.isEmpty,
                   "Renaming keeps the old search alias without creating a duplicate: \(oldName)")
        }
        let machines = ["Жим от груди в тренажёре", "Пуловер в тренажёре",
                        "Сгибание рук в тренажёре", "Жим на плечи в тренажёре"]
        for (index, name) in machines.enumerated() {
            expect(definition(name).id == UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", 0x2F + index)) &&
                   definition(name).trackingType == .weightReps && !definition(name).isCustom,
                   "Machine additions need fixed new IDs and standard weight/repetition entry")
        }
        expect(definition("Жим от груди в тренажёре").category == .chest &&
               definition("Пуловер в тренажёре").category == .back &&
               definition("Сгибание рук в тренажёре").category == .biceps &&
               definition("Жим на плечи в тренажёре").category == .shoulders,
               "Machine additions must use the existing muscle categories")
        expect(targets("Жим от груди в тренажёре") == targets("Жим штанги лёжа") &&
               targets("Жим на плечи в тренажёре") == targets("Жим гантелей сидя") &&
               targets("Сгибание рук в тренажёре") == targets("Подъём штанги на бицепс") &&
               targets("Пуловер в тренажёре").isEmpty,
               "Machine MuscleMaps must reuse their movement's synergists without artificial stabilizer targets")
        let pressTargets: Set<MuscleTarget> = [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Передняя дельта")]
        for name in ["Жим штанги лёжа", "Жим гантелей лёжа", "Жим гантелей на наклонной скамье", "Отжимания на брусьях"] {
            expect(targets(name) == pressTargets, "Chest presses must include triceps and front delts: \(name)")
        }
        expect(targets("Сведение рук в кроссовере").isEmpty, "Cable fly must not count stabilizers")

        let verticalTargets: Set<MuscleTarget> = [MuscleTarget(.biceps, "Бицепс"), MuscleTarget(.biceps, "Брахиалис")]
        for name in ["Подтягивания", "Подтягивания с весом", "Тяга верхнего блока"] {
            expect(targets(name) == verticalTargets, "Vertical pulls must count elbow flexors without grip stabilizers: \(name)")
        }
        for (name, otherBackAccent) in [("Тяга гантели одной рукой", "Средняя часть спины"),
                                         ("Тяга горизонтального блока", "Широчайшие"),
                                         ("Тяга штанги к поясу", "Широчайшие")] {
            expect(targets(name) == verticalTargets.union([MuscleTarget(.back, otherBackAccent), MuscleTarget(.shoulders, "Задняя дельта")]),
                   "Horizontal rows must include the other back accent and rear delt: \(name)")
        }
        expect(targets("Шраги с гантелями").isEmpty && targets("Шраги со штангой").isEmpty,
               "Shrugs must have no artificial secondary targets")
        for name in ["Приседания со штангой", "Жим ногами", "Румынская тяга"] {
            expect(targets(name) == [MuscleTarget(.legs, "Ягодичные")], "Leg compounds must include glutes: \(name)")
        }
        for name in ["Жим гантелей сидя", "Жим штанги стоя"] {
            expect(targets(name) == [MuscleTarget(.triceps, "Трицепс"), MuscleTarget(.shoulders, "Средняя дельта")],
                   "Overhead presses must include triceps and middle delts: \(name)")
        }
        expect(targets("Тяга штанги к подбородку") == [MuscleTarget(.back, "Трапеции")] &&
               targets("Разведение гантелей в наклоне") == [MuscleTarget(.back, "Средняя часть спины")],
               "Shoulder compounds must include their relevant back synergist")
        for name in ["Подъём штанги на бицепс", "Подъём гантелей на бицепс"] {
            expect(targets(name) == [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.forearms, "Плечелучевая")],
                   "Ordinary curls must include brachialis and brachioradialis: \(name)")
        }
        for name in ["Обратные сгибания со штангой", "Обратные сгибания рук в кроссовере"] {
            expect(definition(name).category == .forearms && definition(name).muscleAccent == "Плечелучевая" &&
                   targets(name) == [MuscleTarget(.biceps, "Брахиалис"), MuscleTarget(.biceps, "Бицепс")],
                   "Reverse curls must keep their primary and two distinct biceps accents: \(name)")
        }
        for name in ["Разгибание рук на блоке", "Французский жим", "Разгибание руки из-за головы",
                     "Сгибание запястий со штангой", "Разгибание запястий со штангой"] {
            expect(targets(name).isEmpty, "Isolation exercises must not gain artificial targets: \(name)")
        }

        let calendar = Calendar(identifier: .iso8601)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let analysisDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let pecDeckStore = WorkoutStore(isEphemeral: true)
        pecDeckStore.upsert(WorkoutRecord(title: "Бабочка", date: date, exercises: [
            WorkoutExercise(exerciseID: pecDeck.id, name: pecDeck.name,
                            sets: [SetEntry(weight: 45, repetitions: 7), SetEntry(weight: 45, repetitions: 8),
                                   SetEntry(weight: 45, repetitions: 8)], trackingType: pecDeck.trackingType)
        ]))
        let pecDeckAnalysis = MuscleAnalysisEngine.analyze(store: pecDeckStore, period: .month, relativeTo: analysisDate)
        expect(pecDeckAnalysis.groups.first { $0.target == MuscleTarget(.chest) }?.directSets == 3 &&
               pecDeckAnalysis.groups.allSatisfy { $0.indirectSets == 0 },
               "Recorded Pec Deck sets integrate with the existing MuscleMap and analytics")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("builtin-map-tests-\(UUID().uuidString).json")
        let store = WorkoutStore(fileURL: file)
        let pullup = definition("Подтягивания")
        let reverse = definition("Обратные сгибания рук в кроссовере")
        let row = definition("Тяга горизонтального блока")
        let cardio = definition("Бег")
        let oldMap = MuscleMap(primaryGroup: .back, primaryAccent: "Широчайшие", secondaryMuscles: [MuscleTarget(.biceps, "Бицепс")])
        let record = WorkoutRecord(title: "Карта", date: date, exercises: [
            WorkoutExercise(exerciseID: pullup.id, name: pullup.name, sets: [SetEntry(repetitions: 8)], trackingType: .reps),
            WorkoutExercise(exerciseID: reverse.id, name: reverse.name, sets: [SetEntry(weight: 20, repetitions: 8)]),
            WorkoutExercise(exerciseID: row.id, name: row.name, sets: [SetEntry(weight: 40, repetitions: 8)]),
            WorkoutExercise(exerciseID: cardio.id, name: cardio.name, sets: [SetEntry(durationSeconds: 1200)], trackingType: .cardio)
        ])
        store.upsert(record)
        expect(store.records[0].exercises[1].muscleMapSnapshot?.secondaryMuscles == reverse.secondaryMuscles &&
               store.records[0].exercises[3].muscleMapSnapshot?.primaryGroup == nil,
               "New records must capture current maps; cardio has no strength muscle")
        let result = MuscleAnalysisEngine.analyze(store: store, period: .month, relativeTo: analysisDate)
        expect(result.groups.first { $0.target == MuscleTarget(.biceps) }?.indirectSets == 3 &&
               result.groups.first { $0.target == MuscleTarget(.back) }?.directSets == 2 &&
               result.accents.first { $0.target == MuscleTarget(.back, "Широчайшие") }?.indirectSets == 1,
               "Multiple accents in one muscle group must count once per set at group level")

        var historical = record
        historical.id = UUID()
        historical.exercises = [WorkoutExercise(exerciseID: pullup.id, name: pullup.name,
                                                sets: [SetEntry(repetitions: 6)], trackingType: .reps,
                                                muscleMapSnapshot: oldMap)]
        store.upsert(historical)
        let reloaded = WorkoutStore(fileURL: file)
        expect(reloaded.records.first { $0.id == historical.id }?.exercises[0].muscleMapSnapshot == oldMap,
               "Existing historical snapshots must never be replaced by current built-in maps")
        print("PASS: built-in muscle maps, indirect deduplication and historical snapshots")
    }
}
