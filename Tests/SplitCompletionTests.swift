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
        print("PASS: split completion, continuation, editing and skipping")
    }
}
