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
        print("PASS: split completion, continuation, editing and skipping")
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
}
