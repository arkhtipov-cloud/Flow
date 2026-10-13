import SwiftUI
import Charts
import PhotosUI

private enum PageStyle {
    static let ink = Color(white: 0.06)
    static let muted = Color(white: 0.58)
    static let canvas = Color(red: 0.985, green: 0.985, blue: 0.988)
}

private extension View {
    func floatingTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 80)
        }
    }
}

@MainActor private func insightDisplayEnd(_ interval: DateInterval) -> Date {
    let calendar = WorkoutStore.statisticsCalendar
    return interval.end == calendar.startOfDay(for: interval.end)
        ? interval.end.addingTimeInterval(-1)
        : interval.end
}

private func cardioResultText(_ entry: SetEntry) -> String {
    let time = entry.durationSeconds < 60
        ? "\(entry.durationSeconds) сек"
        : String(format: "%d:%02d", entry.durationSeconds / 60, entry.durationSeconds % 60)
    guard let distance = entry.distanceKilometers, distance > 0 else { return time }
    return "\(time) · \(distance.formatted(.number.precision(.fractionLength(0...2)))) км"
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let record: WorkoutRecord?
    let isTemplate: Bool
}

struct WorkoutEditorView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var record: WorkoutRecord
    @State private var showingExercisePicker = false
    @FocusState private var focusedInput: SetInputField?

    init(record: WorkoutRecord? = nil, isTemplate: Bool = false) {
        _record = State(initialValue: record ?? WorkoutRecord(title: isTemplate ? "Новый шаблон" : "Новая тренировка", isTemplate: isTemplate))
    }

    var body: some View {
        Form {
            Section {
                TextField("Название", text: $record.title)
                    .font(.system(size: 18, weight: .semibold))
                    .focused($focusedInput, equals: .title)
                if !record.isTemplate {
                    DatePicker("Дата", selection: $record.date, displayedComponents: .date)
                }
            }

            ForEach($record.exercises) { $exercise in
                Section {
                    ForEach(Array(exercise.sets.indices), id: \.self) { index in
                        SetInputRow(entry: $exercise.sets[index], number: index + 1, trackingType: exercise.trackingType, previousEntry: index > 0 ? exercise.sets[index - 1] : nil, focusedInput: $focusedInput)
                        .id(exercise.sets[index].id)
                        .swipeActions {
                            if exercise.trackingType != .cardio {
                                Button("Удалить", role: .destructive) {
                                    exercise.sets.remove(at: index)
                                }
                            }
                        }
                    }
                    if exercise.trackingType != .cardio {
                        Button {
                            exercise.sets.append(SetEntry())
                        } label: {
                            Label("Добавить подход", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Button {
                            record.exercises.removeAll { $0.id == exercise.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить упражнение \(exercise.name)")
                    }
                }
            }

            Section {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Выбрать упражнение", systemImage: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle(record.isTemplate ? "Шаблон" : "Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedInput = nil }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    record.title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.upsert(record)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExerciseLibraryView { selected in
                    record.exercises.append(WorkoutExercise(exerciseID: selected.id, name: selected.name, trackingType: selected.trackingType))
                    showingExercisePicker = false
                }
            }
        }
    }
}

private enum SetInputField: Hashable {
    case title
    case weight(UUID)
    case repetitions(UUID)
    case minutes(UUID)
    case seconds(UUID)
    case distance(UUID)
}

private struct SetInputRow: View {
    @Binding var entry: SetEntry
    let number: Int
    let trackingType: ExerciseTrackingType
    let previousEntry: SetEntry?
    @FocusState.Binding var focusedInput: SetInputField?
    @State private var weightText = ""
    @State private var repetitionsText = ""
    @State private var minutesText = ""
    @State private var secondsText = ""
    @State private var distanceText = ""

    var body: some View {
        Group {
            if trackingType == .cardio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Время")
                        .font(.system(size: 13))
                        .foregroundStyle(PageStyle.muted)
                    HStack(spacing: 8) {
                        TextField("мин", text: $minutesText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .minutes(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Минуты кардио")
                        Text(":")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                        TextField("сек", text: $secondsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .seconds(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Секунды кардио")
                    }
                    Text("Дистанция, км")
                        .font(.system(size: 13))
                        .foregroundStyle(PageStyle.muted)
                    TextField("Необязательно", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .focused($focusedInput, equals: .distance(entry.id))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Дистанция в километрах")
                }
            } else {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PageStyle.muted)
                        .frame(width: 22)
                    if trackingType == .weightReps {
                        TextField(previousEntry.map { $0.weight > 0 ? $0.weight.formatted() : "Вес, кг" } ?? "Вес, кг", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedInput, equals: .weight(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Вес, подход \(number)")
                    }
                    if trackingType == .duration {
                        TextField(previousEntry.map { $0.durationSeconds > 0 ? String(format: "%02d", $0.durationSeconds / 60) : "мин" } ?? "мин", text: $minutesText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .minutes(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Минуты, подход \(number)")
                        Text(":")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                        TextField(previousEntry.map { $0.durationSeconds > 0 ? String(format: "%02d", $0.durationSeconds % 60) : "сек" } ?? "сек", text: $secondsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .seconds(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Секунды, подход \(number)")
                    } else {
                        TextField(previousEntry.map { $0.repetitions > 0 ? String($0.repetitions) : "Повторы" } ?? "Повторы", text: $repetitionsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .repetitions(entry.id))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Повторы, подход \(number)")
                    }
                }
            }
        }
        .onAppear {
            weightText = entry.weight == 0 ? "" : entry.weight.formatted()
            repetitionsText = entry.repetitions == 0 ? "" : String(entry.repetitions)
            minutesText = entry.durationSeconds == 0 ? "" : String(format: "%02d", entry.durationSeconds / 60)
            secondsText = entry.durationSeconds == 0 ? "" : String(format: "%02d", entry.durationSeconds % 60)
            distanceText = entry.distanceKilometers?.formatted() ?? ""
        }
        .onChange(of: weightText) { _, newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
            if let value = Double(normalized), value >= 0 { entry.weight = value }
            else if newValue.isEmpty { entry.weight = 0 }
        }
        .onChange(of: repetitionsText) { _, newValue in
            if let value = Int(newValue), value >= 0 { entry.repetitions = value }
            else if newValue.isEmpty { entry.repetitions = 0 }
        }
        .onChange(of: minutesText) { _, _ in updateDuration() }
        .onChange(of: secondsText) { _, _ in updateDuration() }
        .onChange(of: distanceText) { _, newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
            if let value = Double(normalized), value >= 0 { entry.distanceKilometers = value }
            else if newValue.isEmpty { entry.distanceKilometers = nil }
        }
    }

    private func updateDuration() {
        let minutes = Int(minutesText) ?? 0
        let seconds = Int(secondsText) ?? 0
        guard minutes >= 0, (0...59).contains(seconds) else { return }
        entry.durationSeconds = minutes * 60 + seconds
    }
}

struct ExerciseLibraryView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var onSelect: ((ExerciseDefinition) -> Void)? = nil
    @State private var selectedCategory: ExerciseCategory = .chest
    @State private var previewExercise: ExerciseDefinition?

    private struct LibraryGroup: Identifiable {
        let id: Int
        let title: String?
        let exercises: [ExerciseDefinition]
    }

    private var standardGroups: [(String?, [String])] {
        switch selectedCategory {
        case .chest:
            return [("СРЕДНЯЯ ЧАСТЬ ГРУДИ", ["Жим штанги лёжа", "Жим гантелей лёжа", "Сведение рук в кроссовере"]), ("ВЕРХ ГРУДИ", ["Жим гантелей на наклонной скамье"]), ("НИЗ ГРУДИ", ["Отжимания на брусьях"])]
        case .back:
            return [("ШИРОЧАЙШИЕ", ["Подтягивания", "Подтягивания с весом", "Тяга верхнего блока", "Тяга гантели одной рукой"]), ("СРЕДНЯЯ ЧАСТЬ СПИНЫ", ["Тяга горизонтального блока", "Тяга штанги к поясу"]), ("ТРАПЕЦИИ", ["Шраги с гантелями", "Шраги со штангой"])]
        case .legs:
            return [("КВАДРИЦЕПС", ["Приседания со штангой", "Жим ногами", "Разгибание ног"]), ("ЯГОДИЧНЫЕ", ["Румынская тяга"]), ("ЗАДНЯЯ ПОВЕРХНОСТЬ БЕДРА", ["Сгибание ног"]), ("ИКРОНОЖНЫЕ", ["Подъём на носки"])]
        case .shoulders:
            return [("ПЕРЕДНЯЯ ДЕЛЬТА", ["Подъём гантелей перед собой", "Жим гантелей сидя", "Жим штанги стоя"]), ("СРЕДНЯЯ ДЕЛЬТА", ["Подъём гантелей в стороны", "Тяга штанги к подбородку"]), ("ЗАДНЯЯ ДЕЛЬТА", ["Разведение гантелей в наклоне"])]
        case .biceps:
            return [("БИЦЕПС", ["Подъём штанги на бицепс", "Подъём гантелей на бицепс"]), ("БРАХИАЛИС", ["Молотковые сгибания"])]
        case .triceps:
            return [(nil, ["Разгибание рук на блоке", "Французский жим", "Разгибание руки из-за головы"])]
        case .forearms:
            return [("СГИБАТЕЛИ ПРЕДПЛЕЧЬЯ", ["Сгибание запястий со штангой"]), ("РАЗГИБАТЕЛИ ПРЕДПЛЕЧЬЯ", ["Разгибание запястий со штангой"]), ("ПЛЕЧЕЛУЧЕВАЯ", ["Обратные сгибания со штангой"])]
        case .abs:
            return [("ПРЯМАЯ МЫШЦА ЖИВОТА", ["Скручивания", "Подъём ног", "Подъём ног в висе"]), ("КОР", ["Планка"])]
        case .cardio:
            return []
        }
    }

    private var visibleGroups: [LibraryGroup] {
        let available = store.exercises.filter { $0.category == selectedCategory }
        let groups = standardGroups.enumerated().compactMap { index, definition -> LibraryGroup? in
            let standard = definition.1.compactMap { name in
                available.first { !$0.isCustom && $0.name == name }
            }
            let custom = available.filter { $0.isCustom && $0.muscleAccent?.localizedCaseInsensitiveCompare(definition.0 ?? selectedCategory.rawValue) == .orderedSame }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            let exercises = standard + custom
            return exercises.isEmpty ? nil : LibraryGroup(id: index, title: definition.0, exercises: exercises)
        }
        let groupedIDs = Set(groups.flatMap(\.exercises).map(\.id))
        let remaining = available.filter { !groupedIDs.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return remaining.isEmpty ? groups : groups + [LibraryGroup(id: standardGroups.count, title: nil, exercises: remaining)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExerciseCategory.allCases) { category in
                        Button { selectedCategory = category } label: {
                            Text(category.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selectedCategory == category ? .white : PageStyle.ink)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(selectedCategory == category ? PageStyle.ink : Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)

            List {
                ForEach(visibleGroups) { group in
                    if let title = group.title {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PageStyle.muted)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                    }
                    ForEach(group.exercises) { exercise in
                    HStack(spacing: 12) {
                        Button {
                            onSelect?(exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.system(size: 16, weight: .medium))
                                if exercise.isCustom {
                                    Text("Своё")
                                        .font(.system(size: 12))
                                    .foregroundStyle(PageStyle.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            previewExercise = exercise
                        } label: {
                            illustration(for: exercise, size: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Увеличить иллюстрацию: \(exercise.name)")
                    }
                    .foregroundStyle(PageStyle.ink)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(PageStyle.canvas.ignoresSafeArea())
        .tint(PageStyle.ink)
        .navigationTitle("Добавить упражнение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
        }
        .sheet(item: $previewExercise) { exercise in
            NavigationStack {
                GeometryReader { geometry in
                    let previewWidth = geometry.size.width * 0.8
                    let previewHeight = min(geometry.size.height * 0.78, previewWidth)
                    VStack(spacing: 20) {
                        Group {
                            if let customImage = store.customIllustration(for: exercise) {
                                Image(uiImage: customImage)
                                    .resizable()
                                    .scaledToFit()
                            } else if exercise.illustrationID.hasPrefix("chest_") || exercise.illustrationID.hasPrefix("back_") || exercise.illustrationID.hasPrefix("legs_") || exercise.illustrationID.hasPrefix("shoulders_") || exercise.illustrationID.hasPrefix("biceps_") || exercise.illustrationID.hasPrefix("triceps_") || exercise.illustrationID.hasPrefix("forearms_") || exercise.illustrationID.hasPrefix("abs_") || exercise.illustrationID.hasPrefix("cardio_") {
                                Image(exercise.illustrationID)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: exercise.illustrationID)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(previewWidth * 0.28)
                            }
                        }
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()
                        Text(exercise.name)
                            .font(.system(size: 18, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(24)
                .background(PageStyle.canvas.ignoresSafeArea())
                .navigationTitle("Иллюстрация")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { previewExercise = nil }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func illustration(for exercise: ExerciseDefinition, size: CGFloat) -> some View {
        Group {
            if let customImage = store.customIllustration(for: exercise) {
                Image(uiImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if exercise.illustrationID.hasPrefix("chest_") || exercise.illustrationID.hasPrefix("back_") || exercise.illustrationID.hasPrefix("legs_") || exercise.illustrationID.hasPrefix("shoulders_") || exercise.illustrationID.hasPrefix("biceps_") || exercise.illustrationID.hasPrefix("triceps_") || exercise.illustrationID.hasPrefix("forearms_") || exercise.illustrationID.hasPrefix("abs_") || exercise.illustrationID.hasPrefix("cardio_") {
                Image(exercise.illustrationID)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: exercise.illustrationID)
                    .font(.system(size: size * 0.42, weight: .light))
            }
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: size * 0.22))
    }
}
struct WorkoutHistoryView: View {
    @EnvironmentObject private var store: WorkoutStore

    private var months: [(Date, [WorkoutRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.workouts) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { month in
            (month, (grouped[month] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        List {
            if months.isEmpty {
                Text("Сохранённых тренировок пока нет")
                    .foregroundStyle(PageStyle.muted)
            }
            ForEach(months, id: \.0) { month, workouts in
                Section(month.formatted(.dateTime.month(.wide).year()).localizedCapitalized) {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutHistoryDetailView(workoutID: workout.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(workout.date.formatted(.dateTime.day().month(.wide).weekday(.wide)))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(HistorySummary.groups(for: workout, definitions: store.exercises))
                                    .font(.system(size: 13))
                                    .foregroundStyle(PageStyle.muted)
                                let sets = HistorySummary.recordedSetCount(in: workout)
                                let cardio = HistorySummary.cardioCount(in: workout)
                                Text("\(workout.exercises.count) упр. · \(sets) подх." + (cardio > 0 ? " · \(cardio) кардио" : ""))
                                    .font(.system(size: 13))
                                    .foregroundStyle(PageStyle.muted)
                                let records = HistorySummary.recordCount(for: workout, in: store.workouts)
                                if records > 0 {
                                    Label("\(records) личных рекордов", systemImage: "trophy")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .foregroundStyle(PageStyle.ink)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .floatingTabBarClearance()
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("История тренировок")
    }
}

private enum HistorySummary {
    static func groups(for workout: WorkoutRecord, definitions: [ExerciseDefinition]) -> String {
        let categories = workout.exercises.compactMap { exercise in
            (exercise.muscleMapSnapshot?.primaryGroup
                ?? definitions.first(where: { $0.id == exercise.exerciseID })?.category)?.rawValue
        }
        let unique = categories.reduce(into: [String]()) { result, category in
            if !result.contains(category) { result.append(category) }
        }
        return unique.isEmpty ? "Группы не указаны" : unique.joined(separator: " · ")
    }

    static func recordedSets(_ exercise: WorkoutExercise) -> [SetEntry] {
        switch exercise.trackingType {
        case .weightReps, .reps, .duration: exercise.sets.filter { $0.hasRecordedResult(for: exercise.trackingType) }
        case .cardio: []
        }
    }

    static func recordedSetCount(in workout: WorkoutRecord) -> Int {
        workout.exercises.reduce(0) { $0 + recordedSets($1).count }
    }

    static func cardioCount(in workout: WorkoutRecord) -> Int {
        workout.exercises.filter { exercise in
            exercise.trackingType == .cardio && exercise.sets.contains { $0.hasRecordedResult(for: .cardio) }
        }.count
    }

    static func secondsText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) сек" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func resultText(_ entry: SetEntry, type: ExerciseTrackingType) -> String? {
        switch type {
        case .weightReps:
            if entry.weight > 0 && entry.repetitions > 0 {
                return "\(entry.weight.formatted(.number.precision(.fractionLength(0...2)))) кг × \(entry.repetitions)"
            }
            if entry.weight > 0 { return "\(entry.weight.formatted(.number.precision(.fractionLength(0...2)))) кг" }
            if entry.repetitions > 0 { return "\(entry.repetitions) повт." }
            return nil
        case .reps: return entry.repetitions > 0 ? "\(entry.repetitions) повт." : nil
        case .duration: return entry.durationSeconds > 0 ? secondsText(entry.durationSeconds) : nil
        case .cardio:
            if entry.durationSeconds > 0 { return cardioResultText(entry) }
            if let distance = entry.distanceKilometers, distance > 0 {
                return "\(distance.formatted(.number.precision(.fractionLength(0...2)))) км"
            }
            return nil
        }
    }

    static func score(_ exercise: WorkoutExercise, distance: Bool = false) -> Double? {
        let values: [Double] = exercise.sets.compactMap { entry in
            switch exercise.trackingType {
            case .weightReps:
                guard entry.hasRecordedResult(for: .weightReps), (1...12).contains(entry.repetitions) else { return nil }
                return entry.weight * (1 + Double(entry.repetitions) / 30)
            case .reps: return entry.repetitions > 0 ? Double(entry.repetitions) : nil
            case .duration: return entry.durationSeconds > 0 ? Double(entry.durationSeconds) : nil
            case .cardio:
                if distance { return entry.hasRecordedResult(for: .cardio) ? entry.distanceKilometers.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } : nil }
                return entry.durationSeconds > 0 ? Double(entry.durationSeconds) : nil
            }
        }
        return values.max()
    }

    static func metricName(_ type: ExerciseTrackingType, distance: Bool = false) -> String {
        switch type {
        case .weightReps: "Расчётный силовой результат"
        case .reps: "Максимум повторений"
        case .duration: "Максимальная длительность"
        case .cardio: distance ? "Дистанция" : "Длительность"
        }
    }

    static func metricText(_ score: Double, type: ExerciseTrackingType, distance: Bool = false) -> String {
        switch type {
        case .weightReps: "\(score.formatted(.number.precision(.fractionLength(0...1)))) кг"
        case .reps: "\(Int(score)) повт."
        case .duration: secondsText(Int(score))
        case .cardio: distance ? "\(score.formatted(.number.precision(.fractionLength(0...2)))) км" : secondsText(Int(score))
        }
    }

    static func previousExercise(_ exercise: WorkoutExercise, before workout: WorkoutRecord, in workouts: [WorkoutRecord]) -> (Date, WorkoutExercise)? {
        workouts.filter { $0.date < Calendar.current.startOfDay(for: workout.date) }
            .sorted { $0.date > $1.date }
            .compactMap { prior -> (Date, WorkoutExercise)? in
                guard let match = prior.exercises.first(where: { $0.exerciseID == exercise.exerciseID && $0.trackingType == exercise.trackingType }),
                      score(match) != nil else { return nil }
                return (prior.date, match)
            }.first
    }

    @MainActor static func recordCount(for workout: WorkoutRecord, in workouts: [WorkoutRecord]) -> Int {
        let calendar = WorkoutStore.statisticsCalendar
        guard let firstDate = workouts.filter({ $0.exercises.contains { exercise in
            exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
        } }).map(\.date).min(),
              let eligible = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: firstDate)),
              workout.date >= eligible else { return 0 }
        let earlier = workouts.filter { !$0.isTemplate && $0.date < workout.date }
        return workout.exercises.reduce(0) { total, exercise in
            guard exercise.trackingType != .cardio else { return total }
            let prior = earlier.flatMap(\.exercises).filter { $0.exerciseID == exercise.exerciseID && $0.trackingType == exercise.trackingType }
            guard !prior.isEmpty else { return total }
            let dimensions = exercise.trackingType == .cardio ? [false, true] : [false]
            return total + dimensions.filter { distance in
                guard let current = score(exercise, distance: distance),
                      let previous = prior.compactMap({ score($0, distance: distance) }).max() else { return false }
                return current > previous
            }.count
        }
    }
}

private struct WorkoutHistoryDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let workoutID: UUID

    private var workout: WorkoutRecord? { store.workouts.first { $0.id == workoutID } }

    var body: some View {
        ScrollView {
            if let workout {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.date.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 24, weight: .bold))
                        Text(HistorySummary.groups(for: workout, definitions: store.exercises))
                            .foregroundStyle(PageStyle.muted)
                        Text("\(workout.exercises.count) упражнений · \(HistorySummary.recordedSetCount(in: workout)) подходов")
                            .font(.system(size: 14))
                        let records = HistorySummary.recordCount(for: workout, in: store.workouts)
                        if records > 0 {
                            Label("\(records) личных рекордов", systemImage: "trophy")
                                .font(.system(size: 13))
                        }
                    }
                    if let note = workout.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Заметка").font(.system(size: 13, weight: .semibold))
                            Text(note).font(.system(size: 14)).foregroundStyle(PageStyle.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(workout.exercises) { exercise in
                        NavigationLink {
                            ExerciseHistoryChartView(exerciseID: exercise.exerciseID, selectedDate: workout.date)
                        } label: {
                            exerciseCard(exercise, workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(PageStyle.canvas)
        .foregroundStyle(PageStyle.ink)
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exerciseCard(_ exercise: WorkoutExercise, workout: WorkoutRecord) -> some View {
        let entries = exercise.trackingType == .cardio
            ? exercise.sets.filter { HistorySummary.resultText($0, type: .cardio) != nil }
            : HistorySummary.recordedSets(exercise)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exercise.name).font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(PageStyle.muted)
            }
            Text(exercise.trackingType == .cardio ? "Кардио" : "\(entries.count) подходов")
                .font(.system(size: 12)).foregroundStyle(PageStyle.muted)
            if entries.isEmpty {
                Text("Результаты не записаны").font(.system(size: 13)).foregroundStyle(PageStyle.muted)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if let result = HistorySummary.resultText(entry, type: exercise.trackingType) {
                        HStack {
                            Text(exercise.trackingType == .cardio ? "Активность" : "\(index + 1)")
                                .foregroundStyle(PageStyle.muted)
                            Spacer()
                            Text(result)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            if exercise.trackingType == .weightReps,
               let weight = entries.map(\.weight).filter({ $0 > 0 }).max() {
                Text("Максимальный вес · \(weight.formatted(.number.precision(.fractionLength(0...2)))) кг")
                    .font(.system(size: 12)).foregroundStyle(PageStyle.muted)
            }
            if let (date, previous) = HistorySummary.previousExercise(exercise, before: workout, in: store.workouts),
               let old = HistorySummary.score(previous), let current = HistorySummary.score(exercise) {
                let type = exercise.trackingType
                Text("\(HistorySummary.metricName(type)) · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12, weight: .medium))
                Text("Было: \(HistorySummary.metricText(old, type: type)) · Сейчас: \(HistorySummary.metricText(current, type: type))")
                    .font(.system(size: 12)).foregroundStyle(PageStyle.muted)
                Text("Изменение: \(current >= old ? "+" : "")\(HistorySummary.metricText(current - old, type: type))")
                    .font(.system(size: 12)).foregroundStyle(PageStyle.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ExerciseHistoryChartView: View {
    @EnvironmentObject private var store: WorkoutStore
    let exerciseID: UUID
    let selectedDate: Date
    @State private var showDistance = false

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private var exercise: WorkoutExercise? {
        store.workouts.filter { $0.date <= selectedDate }.sorted { $0.date > $1.date }
            .flatMap(\.exercises).first { $0.exerciseID == exerciseID }
    }

    private var points: [Point] {
        store.workouts.filter { $0.date <= selectedDate }.sorted { $0.date < $1.date }.compactMap { workout in
            let scores = workout.exercises.filter { $0.exerciseID == exerciseID && $0.trackingType == exercise?.trackingType }
                .compactMap { HistorySummary.score($0, distance: showDistance) }
            guard let best = scores.max() else { return nil }
            return Point(id: workout.id, date: workout.date, value: best)
        }
    }

    private var hasDistance: Bool {
        store.workouts.filter { $0.date <= selectedDate }.flatMap(\.exercises)
            .contains { $0.exerciseID == exerciseID && $0.trackingType == .cardio && HistorySummary.score($0, distance: true) != nil }
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: 20) {
                    Text(exercise.name).font(.system(size: 24, weight: .bold))
                    if exercise.trackingType == .cardio && hasDistance {
                        Picker("Показатель", selection: $showDistance) {
                            Text("Время").tag(false)
                            Text("Дистанция").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(HistorySummary.metricName(exercise.trackingType, distance: showDistance))
                        .font(.system(size: 14)).foregroundStyle(PageStyle.muted)
                    if points.count >= 2 {
                        Chart(points) { point in
                            LineMark(x: .value("Дата", point.date), y: .value("Результат", point.value))
                                .foregroundStyle(PageStyle.ink)
                            PointMark(x: .value("Дата", point.date), y: .value("Результат", point.value))
                                .foregroundStyle(PageStyle.ink)
                        }
                        .frame(height: 220)
                    } else if let point = points.first {
                        Text(HistorySummary.metricText(point.value, type: exercise.trackingType, distance: showDistance))
                            .font(.system(size: 22, weight: .semibold))
                        Text("Недостаточно данных для динамики")
                            .foregroundStyle(PageStyle.muted)
                    } else {
                        Text("Результаты пока не записаны")
                            .foregroundStyle(PageStyle.muted)
                    }
                    if points.count >= 2 {
                        Text(showDistance ? "км" : exercise.trackingType == .weightReps ? "кг" : exercise.trackingType == .reps ? "повт." : "сек")
                            .font(.system(size: 12)).foregroundStyle(PageStyle.muted)
                    }
                }
                .padding(20)
            }
        }
        .background(PageStyle.canvas)
        .foregroundStyle(PageStyle.ink)
        .navigationTitle("Прогресс")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TemplatesView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var editor: EditorRequest?

    var body: some View {
        List {
            if store.templates.isEmpty {
                ContentUnavailableView("Нет шаблонов", systemImage: "list.bullet.rectangle", description: Text("Создайте шаблон кнопкой +"))
                    .listRowBackground(Color.clear)
            }
            ForEach(store.templates) { template in
                HStack {
                    Button {
                        editor = EditorRequest(record: template, isTemplate: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title).font(.system(size: 16, weight: .semibold))
                            Text("\(template.exercises.count) упр.")
                                .font(.system(size: 13))
                                .foregroundStyle(PageStyle.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        var workout = template
                        workout.id = UUID()
                        workout.date = .now
                        workout.isTemplate = false
                        editor = EditorRequest(record: workout, isTemplate: false)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 25))
                    }
                    .accessibilityLabel("Начать тренировку по шаблону \(template.title)")
                }
                .foregroundStyle(PageStyle.ink)
                .swipeActions {
                    Button("Удалить", role: .destructive) { store.delete(template) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("Шаблоны тренировок")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = EditorRequest(record: nil, isTemplate: true)
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Добавить шаблон")
            }
        }
        .sheet(item: $editor) { request in
            NavigationStack {
                WorkoutEditorView(record: request.record, isTemplate: request.isTemplate)
            }
        }
    }
}

struct WorkoutsTabView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var showingExercisePicker = false
    @State private var showingNoteEditor = false
    @State private var noteDraft = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var expandedExerciseID: UUID?
    @State private var dayTransitionDirection = 1
    @FocusState private var focusedInput: SetInputField?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
    }

    private var selectedWorkouts: [WorkoutRecord] {
        store.records
            .filter { !$0.isTemplate && !$0.exercises.isEmpty && calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }

    private var unfinishedSplitWorkout: WorkoutRecord? {
        selectedWorkouts.first { $0.splitTemplateID != nil && $0.splitTemplateID == store.nextSplitTemplate?.id && $0.splitCompletionRecorded != true }
            ?? selectedWorkouts.last { $0.splitTemplateID != nil && $0.splitCompletionRecorded != true }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Тренировки")
                    .font(.system(size: 38, weight: .bold))
                Spacer()
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: 46, height: 46)
                        .background(Color(white: 0.94), in: Circle())
                }
                .accessibilityLabel("Настройки")
            }
            .padding(.top, 10)

            calendarCard
                .padding(.top, 24)

            List {
                if let next = store.nextSplitTemplate {
                    Section {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Следующая по сплиту")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PageStyle.muted)
                                Text(next.name)
                                    .font(.system(size: 16, weight: .semibold))
                                Text("\(next.exercises.count) упражнений")
                                    .font(.system(size: 12))
                                    .foregroundStyle(PageStyle.muted)
                            }
                            Spacer(minLength: 8)
                            Button("Открыть") {
                                if let record = store.prepareNextSplitWorkout(on: selectedDate) {
                                    selectDate(record.date)
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedExerciseID = record.exercises.first?.id
                                    }
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                        Button("Пропустить") { store.skipNextSplitTemplate(on: selectedDate) }
                            .font(.system(size: 13))
                            .foregroundStyle(PageStyle.muted)
                    }
                }
                if let unfinished = unfinishedSplitWorkout {
                    Section {
                        Button("Завершить тренировку") {
                            focusedInput = nil
                            store.completeSplitWorkout(unfinished.id)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(!store.hasRecordedResult(unfinished.id))
                    }
                }
                if selectedWorkouts.isEmpty {
                    VStack(spacing: 8) {
                        Text("Упражнений пока нет")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(PageStyle.ink)
                        Text("Добавляй упражнения по ходу тренировки")
                            .font(.system(size: 14))
                            .foregroundStyle(PageStyle.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 95)
                    .onTapGesture { focusedInput = nil }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(selectedWorkouts) { workout in
                        ForEach(workout.exercises) { exercise in
                            Section {
                                Button {
                                    focusedInput = nil
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedExerciseID = expandedExerciseID == exercise.id ? nil : exercise.id
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(exercise.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(PageStyle.ink)
                                            Text(exerciseSummary(exercise))
                                                .font(.system(size: 13))
                                                .foregroundStyle(PageStyle.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(PageStyle.muted)
                                            .rotationEffect(.degrees(expandedExerciseID == exercise.id ? 90 : 0))
                                    }
                                    .frame(minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Удалить", role: .destructive) {
                                        removeExercise(exercise, from: workout)
                                    }
                                }
                                if expandedExerciseID == exercise.id {
                                    if let hint = previousSplitHint(for: exercise, in: workout) {
                                        Text(hint)
                                            .font(.system(size: 13))
                                            .foregroundStyle(PageStyle.muted)
                                    }
                                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, entry in
                                        SetInputRow(entry: setBinding(workout: workout, exercise: exercise, set: entry), number: index + 1, trackingType: exercise.trackingType, previousEntry: index > 0 ? exercise.sets[index - 1] : nil, focusedInput: $focusedInput)
                                    .swipeActions {
                                        if exercise.trackingType != .cardio {
                                            Button("Удалить", role: .destructive) {
                                                removeSet(entry, from: exercise, in: workout)
                                            }
                                        }
                                    }
                                    }
                                    if exercise.trackingType != .cardio {
                                        Button {
                                            appendSet(to: exercise, in: workout)
                                        } label: {
                                            Label("Подход", systemImage: "plus")
                                                .font(.system(size: 15, weight: .semibold))
                                                .frame(minHeight: 44)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(daySwipeGesture)
            .onTapGesture { focusedInput = nil }
            .scrollDismissesKeyboard(.interactively)
            .tint(PageStyle.ink)
            .id(selectedDate)
            .transition(.asymmetric(
                insertion: .move(edge: dayTransitionDirection > 0 ? .trailing : .leading),
                removal: .move(edge: dayTransitionDirection > 0 ? .leading : .trailing)
            ))
            .clipped()

            HStack(spacing: 22) {
                NavigationLink("История", destination: WorkoutHistoryView())
                NavigationLink("Шаблоны", destination: TemplatesView())
                if let workout = selectedWorkouts.last {
                    Button("Заметка") {
                        noteDraft = workout.note ?? ""
                        showingNoteEditor = true
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(PageStyle.muted)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            Button {
                showingExercisePicker = true
            } label: {
                Label("Упражнение", systemImage: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(.white)
                    .background(PageStyle.ink, in: Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .padding(.bottom, 12)
        }
        .foregroundStyle(PageStyle.ink)
        .padding(.horizontal, 20)
        .background(PageStyle.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedInput = nil }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExerciseLibraryView { definition in
                    addExercise(definition)
                    showingExercisePicker = false
                }
            }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NavigationStack {
                TextEditor(text: $noteDraft)
                    .padding(16)
                    .navigationTitle("Заметка")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { showingNoteEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                if var workout = selectedWorkouts.last {
                                    let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                    workout.note = text.isEmpty ? nil : text
                                    store.upsert(workout)
                                }
                                showingNoteEditor = false
                            }
                        }
                    }
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveWeek(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                }
                Spacer()
                Text(weekStart.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { moveWeek(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 40, height: 40)
                }
            }
            .font(.system(size: 14, weight: .medium))

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    if let day = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                        Button {
                            selectDate(day)
                        } label: {
                            VStack(spacing: 8) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PageStyle.muted)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : PageStyle.ink)
                                    .frame(width: 38, height: 38)
                                    .background(calendar.isDate(day, inSameDayAs: selectedDate) ? PageStyle.ink : .clear, in: Circle())
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func moveWeek(_ offset: Int) {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return }
        if offset < 0 {
            guard let previousSunday = calendar.date(byAdding: .day, value: -1, to: currentWeek.start) else { return }
            selectDate(previousSunday)
        } else {
            selectDate(currentWeek.end)
        }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 65,
                      abs(horizontal) > abs(value.translation.height) * 1.5,
                      let date = calendar.date(byAdding: .day, value: horizontal < 0 ? 1 : -1, to: selectedDate) else { return }
                selectDate(date)
            }
    }

    private func selectDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard day != selectedDate else { return }
        focusedInput = nil
        dayTransitionDirection = day > selectedDate ? 1 : -1
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = day
            expandedExerciseID = nil
        }
    }

    private func addExercise(_ definition: ExerciseDefinition) {
        var workout = unfinishedSplitWorkout
            ?? selectedWorkouts.last ?? WorkoutRecord(title: "Тренировка", date: selectedDate)
        let exercise = WorkoutExercise(exerciseID: definition.id, name: definition.name, trackingType: definition.trackingType)
        workout.exercises.append(exercise)
        store.upsert(workout)
        withAnimation(.easeInOut(duration: 0.18)) { expandedExerciseID = exercise.id }
    }

    private func previousSplitHint(for exercise: WorkoutExercise, in workout: WorkoutRecord) -> String? {
        guard let previous = store.previousSplitWorkout(for: workout),
              let priorExercise = previous.exercises.first(where: { $0.exerciseID == exercise.exerciseID }),
              let set = priorExercise.sets.last(where: { $0.hasRecordedResult(for: priorExercise.trackingType) }) else { return nil }
        let value: String
        switch priorExercise.trackingType {
        case .weightReps: value = "\(set.weight.formatted()) кг × \(set.repetitions)"
        case .reps: value = "\(set.repetitions) повторов"
        case .duration:
            value = set.durationSeconds < 60 ? "\(set.durationSeconds) сек" : String(format: "%d:%02d", set.durationSeconds / 60, set.durationSeconds % 60)
        case .cardio: value = cardioResultText(set)
        }
        return "Прошлый \(previous.splitTemplateName ?? previous.title) · \(value)"
    }

    private func exerciseSummary(_ exercise: WorkoutExercise) -> String {
        if exercise.trackingType == .cardio {
            guard let activity = exercise.sets.first(where: { $0.durationSeconds > 0 }) else { return "Активность пока не записана" }
            return cardioResultText(activity)
        }
        let recorded = exercise.sets.filter { $0.hasRecordedResult(for: exercise.trackingType) }
        guard let last = recorded.last else { return "Подходов пока нет" }
        let count = recorded.count
        let word = count % 10 == 1 && count % 100 != 11 ? "подход" :
            (2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "подхода" : "подходов"
        let result: String
        switch exercise.trackingType {
        case .weightReps: result = "\(last.weight.formatted()) кг × \(last.repetitions)"
        case .reps: result = "\(last.repetitions) повт."
        case .duration:
            result = last.durationSeconds < 60
                ? "\(last.durationSeconds) сек"
                : String(format: "%d:%02d", last.durationSeconds / 60, last.durationSeconds % 60)
        case .cardio: result = cardioResultText(last)
        }
        return "\(count) \(word) · \(result)"
    }

    private func setBinding(workout: WorkoutRecord, exercise: WorkoutExercise, set: SetEntry) -> Binding<SetEntry> {
        Binding(
            get: { store.records.first(where: { $0.id == workout.id })?.exercises.first(where: { $0.id == exercise.id })?.sets.first(where: { $0.id == set.id }) ?? set },
            set: { updated in
                guard var current = store.records.first(where: { $0.id == workout.id }),
                      let exerciseIndex = current.exercises.firstIndex(where: { $0.id == exercise.id }),
                      let setIndex = current.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) else { return }
                current.exercises[exerciseIndex].sets[setIndex] = updated
                store.upsert(current)
            }
        )
    }

    private func appendSet(to exercise: WorkoutExercise, in workout: WorkoutRecord) {
        guard var current = store.records.first(where: { $0.id == workout.id }),
              let index = current.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        current.exercises[index].sets.append(SetEntry())
        store.upsert(current)
    }

    private func removeSet(_ set: SetEntry, from exercise: WorkoutExercise, in workout: WorkoutRecord) {
        guard var current = store.records.first(where: { $0.id == workout.id }),
              let index = current.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        current.exercises[index].sets.removeAll { $0.id == set.id }
        store.upsert(current)
    }

    private func removeExercise(_ exercise: WorkoutExercise, from workout: WorkoutRecord) {
        guard var current = store.records.first(where: { $0.id == workout.id }) else { return }
        if expandedExerciseID == exercise.id { expandedExerciseID = nil }
        current.exercises.removeAll { $0.id == exercise.id }
        if current.exercises.isEmpty { store.delete(current) }
        else { store.upsert(current) }
    }

}

private enum InsightAnalysisDepth: String, CaseIterable, Identifiable {
    case basic, balanced, detailed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .basic: "Базовая"
        case .balanced: "Сбалансированная"
        case .detailed: "Подробная"
        }
    }
    var explanation: String {
        switch self {
        case .basic: "Рекорды, регулярность и основные изменения результатов"
        case .balanced: "Прогресс, мышечная структура и до 3 инсайтов"
        case .detailed: "До 5 инсайтов, подробная структура и рекомендации"
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage("insights.analysisDepth") private var analysisDepth: InsightAnalysisDepth = .balanced
    @State private var period: StatsPeriod = .month
    @State private var selectedRecommendation: TrainingRecommendation?

    private var analysis: MuscleAnalysisSnapshot {
        MuscleAnalysisEngine.analyze(store: store, period: period)
    }

    private var report: PersonalInsightsResult {
        InsightsEngine.personalInsights(from: analysis)
    }

    private var recommendations: [TrainingRecommendation] {
        RecommendationEngine.recommendations(analysis: analysis, insights: report)
    }

    private var displayedInsights: [PersonalInsight] {
        let insights = report.insights.filter { insight in
            analysisDepth != .basic || insight.category == .achievement || insight.category == .regularity
                || (insight.category == .progress && !insight.id.hasPrefix("stable-"))
        }
        return Array(insights.prefix(analysisDepth == .detailed ? 5 : 3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Инсайты")
                    .font(.system(size: 30, weight: .bold))
                Picker("Период анализа", selection: $period) {
                    ForEach(StatsPeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(periodLabel(analysis.period))
                    .font(.system(size: 13))
                    .foregroundStyle(PageStyle.muted)

                if report.readiness == .collecting {
                    stateCard("Собираем историю тренировок",
                              "Первые наблюдения появятся после семи дней истории и нескольких тренировок с записанными результатами.")
                } else if displayedInsights.isEmpty {
                    stateCard("Пока недостаточно данных",
                              "Для персональных наблюдений нужны выполненные подходы и сопоставимые записи. Продолжай записывать тренировки.")
                } else {
                    ForEach(Array(displayedInsights.enumerated()), id: \.element.id) { index, insight in
                        insightCard(insight, featured: index == 0)
                    }
                }

                if analysisDepth == .detailed && !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("НА ЧТО ОБРАТИТЬ ВНИМАНИЕ")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(PageStyle.muted)
                        ForEach(recommendations) { recommendation in
                            Button {
                                selectedRecommendation = recommendation
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(recommendation.title)
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    Text(recommendation.explanation)
                                        .font(.system(size: 13))
                                        .foregroundStyle(PageStyle.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundStyle(PageStyle.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ПОДРОБНЫЙ АНАЛИЗ")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(PageStyle.muted)
                    if analysisDepth != .basic {
                        NavigationLink {
                            MuscleStructureView(period: period, showsAccents: analysisDepth == .detailed)
                        } label: {
                            detailRow("Мышечная структура")
                        }
                    }
                    NavigationLink {
                        ExerciseAnalysisView(period: period)
                    } label: {
                        detailRow("Прогресс")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .floatingTabBarClearance()
        .background(PageStyle.canvas.ignoresSafeArea())
        .foregroundStyle(PageStyle.ink)
        .navigationTitle("Инсайты")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRecommendation) { recommendation in
            RecommendationDetailView(recommendation: recommendation, period: period)
        }
    }

    private func insightCard(_ insight: PersonalInsight, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: featured ? 10 : 6) {
            Text(insight.category.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(PageStyle.muted)
            Text(insight.title)
                .font(.system(size: featured ? 22 : 17, weight: .semibold))
            Text(insight.explanation)
                .font(.system(size: 14))
            if let evidence = insight.metrics.first {
                Text("\(evidence.name): \(evidence.value.formatted(.number.precision(.fractionLength(0...1)))) \(evidence.unit)")
                    .font(.system(size: 12))
                    .foregroundStyle(PageStyle.muted)
            }
            Text(periodLabel(insight.period))
                .font(.system(size: 12))
                .foregroundStyle(PageStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(featured ? 20 : 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stateCard(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(message).font(.system(size: 14)).foregroundStyle(PageStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func detailRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(PageStyle.ink)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func periodLabel(_ interval: DateInterval) -> String {
        "\(interval.start.formatted(date: .abbreviated, time: .omitted)) — \(insightDisplayEnd(interval).formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct RecommendationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recommendation: TrainingRecommendation
    let period: StatsPeriod

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(recommendation.category.label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(PageStyle.muted)
                    Text(recommendation.title)
                        .font(.system(size: 21, weight: .semibold))
                    Text(recommendation.explanation)
                        .font(.system(size: 14))
                    Text("Основание · \(recommendation.period.start.formatted(date: .abbreviated, time: .omitted)) — \(insightDisplayEnd(recommendation.period).formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(PageStyle.muted)
                    Text("Наблюдений: \(recommendation.observationCount)")
                        .font(.system(size: 13))
                    ForEach(Array(recommendation.metrics.enumerated()), id: \.offset) { _, evidence in
                        HStack {
                            Text(evidence.name)
                            Spacer()
                            Text("\(evidence.value.formatted(.number.precision(.fractionLength(0...1)))) \(evidence.unit)")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))
                    }
                    if let action = recommendation.action {
                        NavigationLink {
                            switch action {
                            case .muscleStructure(let category):
                                if let category {
                                    MuscleAccentView(period: period, category: category)
                                } else {
                                    MuscleStructureView(period: period)
                                }
                            case .exerciseProgress(let id):
                                ExerciseHistoryChartView(exerciseID: id, selectedDate: .now)
                            }
                        } label: {
                            HStack {
                                Text("Открыть подробный анализ")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PageStyle.ink)
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(PageStyle.canvas.ignoresSafeArea())
            .foregroundStyle(PageStyle.ink)
            .navigationTitle("Основание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension RecommendationCategory {
    var label: String {
        switch self {
        case .muscleAccents: "Мышечные акценты"
        case .exerciseProgress: "Прогресс"
        case .trainingDistribution: "Структура тренировок"
        case .regularity: "Регулярность"
        }
    }
}
private extension PersonalInsightCategory {
    var label: String {
        switch self {
        case .muscleStructure: "Мышечная структура"
        case .progress: "Прогресс"
        case .regularity: "Регулярность"
        case .achievement: "Достижение"
        }
    }
}

private struct MuscleStructureView: View {
    @EnvironmentObject private var store: WorkoutStore
    let period: StatsPeriod
    var showsAccents = true

    private var analysis: MuscleAnalysisSnapshot {
        MuscleAnalysisEngine.analyze(store: store, period: period)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(period.rawValue) · \(analysis.regularity.workoutCount) тренировок")
                    .font(.system(size: 13)).foregroundStyle(PageStyle.muted)
                if analysis.groups.allSatisfy({ $0.observationCount == 0 }) {
                    Text("Пока нет выполненных подходов для анализа мышечной структуры.")
                        .font(.system(size: 14)).foregroundStyle(PageStyle.muted)
                        .padding(18)
                } else {
                    ForEach(analysis.groups) { group in
                        if showsAccents {
                            NavigationLink {
                                MuscleAccentView(period: period, category: group.target.category)
                            } label: {
                                muscleGroupRow(group, showsChevron: true)
                            }
                        } else {
                            muscleGroupRow(group, showsChevron: false)
                        }
                    }
                }
            }
            .padding(18)
        }
        .floatingTabBarClearance()
        .background(PageStyle.canvas.ignoresSafeArea())
        .navigationTitle("Мышечная структура")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func muscleGroupRow(_ group: MuscleActivityResult, showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.target.category.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Text("Прямые подходы: \(group.directSets) · Косвенные: \(group.indirectSets)")
            Text("Тренировочных дней: \(group.trainingDays)")
        }
        .font(.system(size: 13))
        .foregroundStyle(PageStyle.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MuscleAccentView: View {
    @EnvironmentObject private var store: WorkoutStore
    let period: StatsPeriod
    let category: ExerciseCategory

    private var accents: [MuscleActivityResult] {
        MuscleAnalysisEngine.analyze(store: store, period: period).accents
            .filter { $0.target.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if accents.isEmpty {
                    Text("Для отдельных акцентов пока нет записанных подходов.")
                        .foregroundStyle(PageStyle.muted)
                } else {
                    ForEach(accents) { accent in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(accent.target.accent ?? "Акцент")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Прямые подходы: \(accent.directSets)")
                            Text("Косвенное участие: \(accent.indirectSets)")
                            Text("Тренировочных дней: \(accent.trainingDays)")
                        }
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(18)
        }
        .background(PageStyle.canvas.ignoresSafeArea())
        .foregroundStyle(PageStyle.ink)
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExerciseAnalysisView: View {
    @EnvironmentObject private var store: WorkoutStore
    let period: StatsPeriod

    private var analysis: MuscleAnalysisSnapshot {
        MuscleAnalysisEngine.analyze(store: store, period: period)
    }

    private var comparable: [ExerciseProgressResult] {
        analysis.exercises.filter(\.canCompare)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(period.rawValue) · результаты одного упражнения сравниваются только с его историей")
                    .font(.system(size: 13)).foregroundStyle(PageStyle.muted)
                if comparable.isEmpty {
                    Text("Пока нет сопоставимых результатов. Нужны повторные выполнения одного упражнения.")
                        .font(.system(size: 14)).foregroundStyle(PageStyle.muted)
                        .padding(18)
                } else {
                    ForEach(comparable) { result in
                        NavigationLink {
                            ExerciseHistoryChartView(exerciseID: result.exerciseID, selectedDate: .now)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(result.name).font(.system(size: 17, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text("\(result.metric.label) · \(result.observationCount) наблюдений")
                                    .foregroundStyle(PageStyle.muted)
                                if let latest = result.latest, let previous = result.previous {
                                    Text("\(previous.formatted(.number.precision(.fractionLength(0...1)))) → \(latest.formatted(.number.precision(.fractionLength(0...1)))) \(result.metric.unit)")
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(PageStyle.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding(18)
        }
        .floatingTabBarClearance()
        .background(PageStyle.canvas.ignoresSafeArea())
        .navigationTitle("Прогресс")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension ExerciseResultMetric {
    var label: String {
        switch self {
        case .estimatedOneRepMax: "Расчётный силовой результат"
        case .repetitions: "Повторения"
        case .durationSeconds, .cardioDurationSeconds: "Длительность"
        case .cardioDistanceKilometers: "Дистанция"
        }
    }
    var unit: String {
        switch self {
        case .estimatedOneRepMax: "кг e1RM"
        case .repetitions: "повт."
        case .durationSeconds, .cardioDurationSeconds: "сек."
        case .cardioDistanceKilometers: "км"
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage("insights.analysisDepth") private var analysisDepth: InsightAnalysisDepth = .balanced

    var body: some View {
        Form {
            Section {
                NavigationLink("Свои упражнения", destination: CustomExercisesView())
                NavigationLink("Сплит тренировок", destination: SplitSettingsView())
            }
            Section("Тренировки") {
                Stepper(value: $store.weeklyGoal, in: 1...7) {
                    HStack {
                        Text("Цель на неделю")
                        Spacer()
                        Text("\(store.weeklyGoal)")
                            .foregroundStyle(PageStyle.muted)
                    }
                }
            }
            Section("Инсайты") {
                Picker("Глубина анализа", selection: $analysisDepth) {
                    ForEach(InsightAnalysisDepth.allCases) { depth in
                        Text(depth.title).tag(depth)
                    }
                }
                Text(analysisDepth.explanation)
                    .font(.footnote)
                    .foregroundStyle(PageStyle.muted)
            }
            if let error = store.saveError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("Настройки")
    }
}

private struct CustomExercisesView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var showingEditor = false
    @State private var editingExercise: ExerciseDefinition?

    private var customExercises: [ExerciseDefinition] {
        store.exercises.filter(\.isCustom).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Button {
                editingExercise = nil
                showingEditor = true
            } label: {
                Label("Добавить упражнение", systemImage: "plus")
                    .frame(minHeight: 44)
            }

            if customExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Своих упражнений пока нет")
                        .font(.system(size: 16, weight: .medium))
                    Text("Добавь первое упражнение")
                        .font(.system(size: 14))
                        .foregroundStyle(PageStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
            } else {
                ForEach(customExercises) { exercise in
                    Button {
                        editingExercise = exercise
                        showingEditor = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.system(size: 16, weight: .medium))
                                Text([exercise.category.rawValue, exercise.muscleAccent].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 13))
                                    .foregroundStyle(PageStyle.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PageStyle.muted)
                        }
                        .frame(minHeight: 50)
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) { store.deleteExercise(exercise) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("Свои упражнения")
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                CustomExerciseEditorView(exercise: editingExercise)
            }
            .presentationDetents([.medium])
        }
    }
}

private struct CustomExerciseEditorView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDefinition?
    @State private var name: String
    @State private var category: ExerciseCategory
    @State private var muscleAccent: String
    @State private var selectedSecondary: Set<MuscleTarget>
    @State private var trackingType: ExerciseTrackingType
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var removeImage = false

    private var shownImage: UIImage? {
        if let imageData { return UIImage(data: imageData) }
        guard !removeImage, let exercise else { return nil }
        return store.customIllustration(for: exercise)
    }

    private var secondarySelection: [MuscleTarget] {
        ExerciseCategory.allCases.flatMap { group in
            group.accents.map { MuscleTarget(group, $0) }
        }.filter { selectedSecondary.contains($0) }
    }

    init(exercise: ExerciseDefinition?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _category = State(initialValue: exercise?.category ?? .chest)
        let initialCategory = exercise?.category ?? .chest
        let previousAccent = exercise?.muscleAccent ?? ""
        let initialAccent = initialCategory.accents.contains(previousAccent) ? previousAccent
            : (exercise != nil && initialCategory.accents.count > 1 ? "" : initialCategory.accents.first ?? "")
        _muscleAccent = State(initialValue: initialAccent)
        _selectedSecondary = State(initialValue: Set(exercise?.secondaryMuscles ?? []))
        _trackingType = State(initialValue: exercise?.trackingType ?? .weightReps)
    }

    var body: some View {
        Form {
            TextField("Название упражнения", text: $name)
            Picker("Группа мышц", selection: $category) {
                ForEach(ExerciseCategory.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            if category.accents.count > 1 {
                Picker("Основной акцент", selection: $muscleAccent) {
                    if muscleAccent.isEmpty { Text("Выберите акцент").tag("") }
                    ForEach(category.accents, id: \.self) { accent in
                        Text(accent).tag(accent)
                    }
                }
            } else if let accent = category.accents.first {
                LabeledContent("Основной акцент", value: accent)
            }
            if category != .cardio && trackingType != .cardio {
                DisclosureGroup("Дополнительные мышцы") {
                    ForEach(ExerciseCategory.allCases.filter { $0 != .cardio }) { group in
                        DisclosureGroup(group.rawValue) {
                            ForEach(group.accents, id: \.self) { accent in
                                let target = MuscleTarget(group, accent)
                                if !(group == category && accent == muscleAccent) {
                                    Toggle(accent, isOn: Binding(
                                        get: { selectedSecondary.contains(target) },
                                        set: { enabled in
                                            if enabled { selectedSecondary.insert(target) }
                                            else { selectedSecondary.remove(target) }
                                        }
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            Picker("Тип записи", selection: $trackingType) {
                ForEach(ExerciseTrackingType.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack {
                    Text("Иллюстрация")
                    Spacer()
                    if let image = shownImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Выбрать")
                            .foregroundStyle(PageStyle.muted)
                    }
                }
            }
            if shownImage != nil {
                Button("Убрать иллюстрацию") {
                    selectedPhoto = nil
                    imageData = nil
                    removeImage = true
                }
                .foregroundStyle(PageStyle.muted)
            }
        }
        .onChange(of: category) { _, newCategory in
            muscleAccent = newCategory.accents.first ?? ""
            if newCategory == .cardio { selectedSecondary.removeAll() }
            else { selectedSecondary.remove(MuscleTarget(newCategory, muscleAccent)) }
        }
        .onChange(of: muscleAccent) { _, newAccent in
            selectedSecondary.remove(MuscleTarget(category, newAccent))
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                    imageData = data
                    removeImage = false
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle(exercise == nil ? "Новое упражнение" : "Изменить упражнение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    if let exercise {
                        store.renameExercise(exercise, to: name, category: category, trackingType: trackingType,
                                             muscleAccent: muscleAccent, secondaryMuscles: secondarySelection,
                                             imageData: imageData, removeImage: removeImage)
                    } else {
                        store.addExercise(named: name, category: category, trackingType: trackingType,
                                          muscleAccent: muscleAccent, secondaryMuscles: secondarySelection,
                                          imageData: imageData)
                    }
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!category.accents.isEmpty && !category.accents.contains(muscleAccent)))
            }
        }
    }
}

private struct SplitSettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var editingTemplate: SplitWorkoutTemplate?

    var body: some View {
        List {
            Section {
                Toggle("Использовать сплит", isOn: Binding(
                    get: { store.splitPlan.isEnabled },
                    set: { store.setSplitEnabled($0) }
                ))
            }

            Section {
                if store.splitPlan.templates.isEmpty {
                    Text("Добавь первую тренировку цикла")
                        .foregroundStyle(PageStyle.muted)
                }
                ForEach(store.splitPlan.templates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.name)
                                    .font(.system(size: 16, weight: .medium))
                                Text("\(template.exercises.count) упражнений")
                                    .font(.system(size: 13))
                                    .foregroundStyle(PageStyle.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PageStyle.muted)
                        }
                        .frame(minHeight: 48)
                    }
                }
                .onDelete(perform: store.deleteSplitTemplates)
                .onMove(perform: store.moveSplitTemplates)

                Button {
                    editingTemplate = SplitWorkoutTemplate(name: "")
                } label: {
                    Label("Добавить тренировку", systemImage: "plus")
                        .frame(minHeight: 44)
                }
            } header: {
                Text("Цикл тренировок")
            } footer: {
                Text("Следующая тренировка определяется порядком цикла, а не днём недели.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("Сплит тренировок")
        .toolbar { EditButton() }
        .sheet(item: $editingTemplate) { template in
            NavigationStack {
                SplitTemplateEditorView(template: template)
            }
        }
    }
}

private struct SplitTemplateEditorView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var template: SplitWorkoutTemplate
    @State private var showingExercisePicker = false

    init(template: SplitWorkoutTemplate) {
        _template = State(initialValue: template)
    }

    var body: some View {
        List {
            Section("Название") {
                TextField("Например, Push", text: $template.name)
            }
            Section("Упражнения") {
                ForEach(template.exercises) { exercise in
                    Text(exercise.name)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .onDelete { template.exercises.remove(atOffsets: $0) }
                .onMove { template.exercises.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Добавить упражнение", systemImage: "plus")
                        .frame(minHeight: 44)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PageStyle.canvas)
        .tint(PageStyle.ink)
        .navigationTitle("Тренировка сплита")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.upsertSplitTemplate(template)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || template.exercises.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExerciseLibraryView { exercise in
                    if !template.exercises.contains(where: { $0.exerciseID == exercise.id }) {
                        template.exercises.append(SplitTemplateExercise(exerciseID: exercise.id, name: exercise.name, trackingType: exercise.trackingType))
                    }
                    showingExercisePicker = false
                }
            }
        }
    }
}
