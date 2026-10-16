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
        print("PASS: split completion, continuation, editing and skipping")
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
            ExerciseDefinition.builtIn.first { $0.name == name }!
        }
        func targets(_ name: String) -> Set<MuscleTarget> {
            Set(definition(name).secondaryMuscles)
        }
        let machineQueries = ["Pec Deck", "Жим в грудном тренажёре", "Тяга верхнего блока", "Горизонтальная тяга блока",
                              "Пуловер в тренажёре", "Жим ногами", "Разгибание ног", "Сгибание ног",
                              "Сгибание рук в тренажёре на бицепс", "Разгибание рук на верхнем блоке", "Жим плечами в тренажёре"]
        for query in machineQueries {
            expect(builtIn.filter { $0.matchesSearch(query) }.count == 1,
                   "Every requested machine exercise or synonym must resolve once: \(query)")
        }
        for (oldName, newName) in [
            ("Бабочка (сведение рук в тренажёре)", "Бабочка"),
            ("Жим в грудном тренажёре", "Жим от груди в тренажёре"),
            ("Сгибание рук в тренажёре на бицепс", "Сгибание рук в тренажёре"),
            ("Жим плечами в тренажёре", "Жим на плечи в тренажёре")
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
