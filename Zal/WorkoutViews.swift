import SwiftUI
import Charts
import PhotosUI
import UniformTypeIdentifiers

private enum PageStyle {
    static let ink = ThemePalette.ink
    static let muted = ThemePalette.muted
    static let canvas = ThemePalette.canvas
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

private struct ExerciseReorderModifier: ViewModifier {
    let workoutID: UUID
    let exerciseID: UUID
    let move: (UUID) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrag {
                NSItemProvider(object: "\(workoutID.uuidString)/\(exerciseID.uuidString)" as NSString)
            }
            .onDrop(of: [UTType.text], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String else { return }
                    let parts = text.split(separator: "/")
                    guard parts.count == 2, UUID(uuidString: String(parts[0])) == workoutID,
                          let sourceID = UUID(uuidString: String(parts[1])), sourceID != exerciseID else { return }
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 0.22)) { move(sourceID) }
                    }
                }
                return true
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 21)
                        .stroke(ThemePalette.ink.opacity(0.3), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
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
                        SetInputRow(entry: $exercise.sets[index], number: index + 1, trackingType: exercise.trackingType, previousEntry: index > 0 ? exercise.sets[index - 1] : nil, inCard: false, focusedInput: $focusedInput)
                        .id(exercise.sets[index].id)
                        .swipeActions {
                            if exercise.trackingType != .cardio {
                                Button("Удалить", role: .destructive) {
                                    exercise.sets.remove(at: index)
                                }
                                .tint(.red)
                                .foregroundStyle(.white)
                                .buttonStyle(.automatic)
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
                    .contentShape(Rectangle())
                    .modifier(ExerciseReorderModifier(workoutID: record.id, exerciseID: exercise.id) { sourceID in
                        record.moveExercise(sourceID, to: exercise.id)
                    })
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

private struct WorkoutCardFieldStyle: ViewModifier {
    let inCard: Bool

    func body(content: Content) -> some View {
        if inCard {
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(ThemePalette.raised, in: RoundedRectangle(cornerRadius: 10))
        } else {
            content.textFieldStyle(.roundedBorder)
        }
    }
}

private struct SetInputRow: View {
    @Binding var entry: SetEntry
    let number: Int
    let trackingType: ExerciseTrackingType
    let previousEntry: SetEntry?
    let inCard: Bool
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
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
                            .accessibilityLabel("Минуты кардио")
                        Text(":")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                        TextField("сек", text: $secondsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .seconds(entry.id))
                            .multilineTextAlignment(.center)
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
                            .accessibilityLabel("Секунды кардио")
                    }
                    Text("Дистанция, км")
                        .font(.system(size: 13))
                        .foregroundStyle(PageStyle.muted)
                    TextField("Необязательно", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .focused($focusedInput, equals: .distance(entry.id))
                        .modifier(WorkoutCardFieldStyle(inCard: inCard))
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
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
                            .accessibilityLabel("Вес, подход \(number)")
                    }
                    if trackingType == .duration {
                        TextField(previousEntry.map { $0.durationSeconds > 0 ? String(format: "%02d", $0.durationSeconds / 60) : "мин" } ?? "мин", text: $minutesText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .minutes(entry.id))
                            .multilineTextAlignment(.center)
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
                            .accessibilityLabel("Минуты, подход \(number)")
                        Text(":")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                        TextField(previousEntry.map { $0.durationSeconds > 0 ? String(format: "%02d", $0.durationSeconds % 60) : "сек" } ?? "сек", text: $secondsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .seconds(entry.id))
                            .multilineTextAlignment(.center)
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
                            .accessibilityLabel("Секунды, подход \(number)")
                    } else {
                        TextField(previousEntry.map { $0.repetitions > 0 ? String($0.repetitions) : "Повторы" } ?? "Повторы", text: $repetitionsText)
                            .keyboardType(.numberPad)
                            .focused($focusedInput, equals: .repetitions(entry.id))
                            .multilineTextAlignment(.center)
                            .modifier(WorkoutCardFieldStyle(inCard: inCard))
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
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var previewExercise: ExerciseDefinition?

    private struct LibraryGroup: Identifiable {
        let id: Int
        let title: String?
        let exercises: [ExerciseDefinition]
    }

    private enum LibraryRow: Identifiable {
        case heading(Int, String)
        case exercise(ExerciseDefinition)

        var id: String {
            switch self {
            case .heading(let id, _): "heading-\(id)"
            case .exercise(let exercise): exercise.id.uuidString
            }
        }
    }

    private var visibleRows: [LibraryRow] {
        visibleGroups.flatMap { group in
            let heading = group.title.map { [LibraryRow.heading(group.id, $0)] } ?? []
            return heading + group.exercises.map(LibraryRow.exercise)
        }
    }

    private var standardGroups: [(String?, [String])] {
        switch selectedCategory {
        case .chest:
            return [("СРЕДНЯЯ ЧАСТЬ ГРУДИ", ["Жим штанги лёжа", "Жим гантелей лёжа", "Сведение рук в кроссовере", "Бабочка", "Жим от груди в тренажёре"]), ("ВЕРХ ГРУДИ", ["Жим гантелей на наклонной скамье"]), ("НИЗ ГРУДИ", ["Отжимания на брусьях"])]
        case .back:
            return [("ШИРОЧАЙШИЕ", ["Подтягивания", "Подтягивания с весом", "Тяга верхнего блока", "Тяга гантели одной рукой", "Пуловер в тренажёре"]), ("СРЕДНЯЯ ЧАСТЬ СПИНЫ", ["Тяга горизонтального блока", "Тяга штанги к поясу"]), ("ТРАПЕЦИИ", ["Шраги с гантелями", "Шраги со штангой"])]
        case .legs:
            return [("КВАДРИЦЕПС", ["Приседания со штангой", "Жим ногами", "Разгибание ног"]), ("ЯГОДИЧНЫЕ", ["Румынская тяга"]), ("ЗАДНЯЯ ПОВЕРХНОСТЬ БЕДРА", ["Сгибание ног"]), ("ИКРОНОЖНЫЕ", ["Подъём на носки"])]
        case .shoulders:
            return [("ПЕРЕДНЯЯ ДЕЛЬТА", ["Подъём гантелей перед собой", "Жим гантелей сидя", "Жим штанги стоя", "Жим на плечи в тренажёре"]), ("СРЕДНЯЯ ДЕЛЬТА", ["Подъём гантелей в стороны", "Тяга штанги к подбородку"]), ("ЗАДНЯЯ ДЕЛЬТА", ["Разведение гантелей в наклоне"])]
        case .biceps:
            return [("БИЦЕПС", ["Подъём штанги на бицепс", "Подъём гантелей на бицепс", "Сгибание рук в тренажёре"]), ("БРАХИАЛИС", ["Молотковые сгибания"])]
        case .triceps:
            return [(nil, ["Разгибание рук на блоке", "Французский жим", "Разгибание руки из-за головы"])]
        case .forearms:
            return [("СГИБАТЕЛИ ПРЕДПЛЕЧЬЯ", ["Сгибание запястий со штангой"]), ("РАЗГИБАТЕЛИ ПРЕДПЛЕЧЬЯ", ["Разгибание запястий со штангой"]), ("ПЛЕЧЕЛУЧЕВАЯ", ["Обратные сгибания со штангой", "Обратные сгибания рук в кроссовере"])]
        case .abs:
            return [("ПРЯМАЯ МЫШЦА ЖИВОТА", ["Скручивания", "Подъём ног", "Подъём ног в висе"]), ("КОР", ["Планка"])]
        case .cardio:
            return []
        }
    }

    private var visibleGroups: [LibraryGroup] {
        if isSearchPresented || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = store.exercises.filter { $0.matchesSearch(searchText) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            return matches.isEmpty ? [] : [LibraryGroup(id: 0, title: nil, exercises: matches)]
        }
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
            if !isSearchPresented {
                ScrollViewReader { categoryProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ExerciseCategory.allCases) { category in
                                Button { selectedCategory = category } label: {
                                    Text(category.rawValue)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(selectedCategory == category ? ThemePalette.onAccent : PageStyle.ink)
                                        .padding(.horizontal, 16)
                                        .frame(height: 38)
                                        .background(selectedCategory == category ? PageStyle.ink : ThemePalette.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .id(category)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: selectedCategory) { _, category in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            categoryProxy.scrollTo(category, anchor: .center)
                        }
                    }
                    .onAppear {
                        categoryProxy.scrollTo(selectedCategory, anchor: .center)
                    }
                }
                .padding(.vertical, 14)
            }

            List {
                // One stable List row per ID, including when search removes group headings.
                ForEach(visibleRows) { row in
                    switch row {
                    case .heading(_, let title):
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PageStyle.muted)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                    case .exercise(let exercise):
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
                                ExerciseLibraryIllustration(exercise: exercise, size: 48)
                                    .equatable()
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 25).onEnded { value in
                    let horizontal = value.translation.width
                    guard !isSearchPresented, abs(horizontal) > 50,
                          abs(horizontal) > abs(value.translation.height) * 1.2,
                          let index = ExerciseCategory.allCases.firstIndex(of: selectedCategory) else { return }
                    let next = index + (horizontal < 0 ? 1 : -1)
                    guard ExerciseCategory.allCases.indices.contains(next) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = ExerciseCategory.allCases[next]
                    }
                }
            )
        }
        .background(PageStyle.canvas.ignoresSafeArea())
        .tint(PageStyle.ink)
        .navigationTitle("Добавить упражнение")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Поиск упражнений")
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

}

private struct ExerciseLibraryIllustration: View, Equatable {
    @EnvironmentObject private var store: WorkoutStore
    let exercise: ExerciseDefinition
    let size: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.exercise == rhs.exercise && lhs.size == rhs.size
    }

    var body: some View {
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
                    .font(.system(size: size * 0.42, weight: .light))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .swipeActions {
                            Button("Удалить", role: .destructive) { store.delete(workout) }
                                .tint(.red)
                                .foregroundStyle(.white)
                                .buttonStyle(.automatic)
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
        let values: [Double] = exercise.analysisSets.compactMap { entry in
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
                        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 18))
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
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 18))
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
                        .tint(.red)
                        .foregroundStyle(.white)
                        .buttonStyle(.automatic)
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
    @State private var displayedCalendarDate = Calendar.current.startOfDay(for: .now)
    @State private var expandedExerciseID: UUID?
    @State private var pendingScrollSetID: UUID?
    @State private var dayTransitionDirection = 1
    @State private var weekDragOffset: CGFloat = 0
    @State private var isWeekSettling = false
    @FocusState private var focusedInput: SetInputField?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: displayedCalendarDate)?.start ?? displayedCalendarDate
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
                        .background(ThemePalette.soft, in: Circle())
                }
                .accessibilityLabel("Настройки")
            }
            .padding(.top, 10)

            calendarCard
                .padding(.top, 24)
                .padding(.bottom, 12)

            ScrollViewReader { scrollProxy in
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
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(exerciseCardBackground(top: true, bottom: expandedExerciseID != exercise.id || (exercise.trackingType == .cardio && exercise.sets.isEmpty && previousSplitHint(for: exercise, in: workout) == nil)))
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .modifier(ExerciseReorderModifier(workoutID: workout.id, exerciseID: exercise.id) { sourceID in
                                    store.moveExercise(sourceID, to: exercise.id, in: workout.id)
                                })
                                .swipeActions {
                                    Button("Удалить", role: .destructive) {
                                        removeExercise(exercise, from: workout)
                                    }
                                    .tint(.red)
                                    .foregroundStyle(.white)
                                    .buttonStyle(.automatic)
                                }
                                if expandedExerciseID == exercise.id {
                                    if let hint = previousSplitHint(for: exercise, in: workout) {
                                        Text(hint)
                                            .font(.system(size: 13))
                                            .foregroundStyle(PageStyle.muted)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(exerciseCardBackground(top: false, bottom: exercise.trackingType == .cardio && exercise.sets.isEmpty))
                                            .listRowInsets(EdgeInsets())
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                    }
                                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, entry in
                                        SetInputRow(entry: setBinding(workout: workout, exercise: exercise, set: entry), number: index + 1, trackingType: exercise.trackingType, previousEntry: index > 0 ? exercise.sets[index - 1] : nil, inCard: true, focusedInput: $focusedInput)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(exerciseCardBackground(top: false, bottom: exercise.trackingType == .cardio && index == exercise.sets.count - 1))
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions {
                                        if exercise.trackingType != .cardio {
                                            Button("Удалить", role: .destructive) {
                                                removeSet(entry, from: exercise, in: workout)
                                            }
                                            .tint(.red)
                                            .foregroundStyle(.white)
                                            .buttonStyle(.automatic)
                                        }
                                    }
                                    .id(entry.id)
                                    }
                                    if exercise.trackingType != .cardio {
                                        Button {
                                            focusedInput = nil
                                            appendSet(to: exercise, in: workout)
                                        } label: {
                                            Label("Подход", systemImage: "plus")
                                                .font(.system(size: 15, weight: .semibold))
                                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .background(exerciseCardBackground(top: false, bottom: true))
                                        .listRowInsets(EdgeInsets())
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(10)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedInput != nil {
                    HStack {
                        Spacer()
                        Button("Готово") { focusedInput = nil }
                            .font(.system(size: 15, weight: .semibold))
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
            .background(PageStyle.canvas.contentShape(Rectangle()).onTapGesture { focusedInput = nil })
            .scrollDismissesKeyboard(.interactively)
            .tint(PageStyle.ink)
            .id(selectedDate)
            .transition(.asymmetric(
                insertion: .move(edge: dayTransitionDirection > 0 ? .trailing : .leading),
                removal: .move(edge: dayTransitionDirection > 0 ? .leading : .trailing)
            ))
            .clipped()
            .onChange(of: pendingScrollSetID) { _, setID in
                guard let setID else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(setID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: focusedInput) { _, input in
                guard let input else { return }
                let setID: UUID
                switch input {
                case .title: return
                case .weight(let id), .repetitions(let id), .minutes(let id), .seconds(let id), .distance(let id):
                    setID = id
                }
                Task { @MainActor in
                    await Task.yield()
                    scrollProxy.scrollTo(setID, anchor: .center)
                }
            }
            }

            if focusedInput == nil {
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
                        .foregroundStyle(ThemePalette.onAccent)
                        .background(PageStyle.ink, in: Capsule())
                }
                .buttonStyle(PressableCardStyle())
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(PageStyle.ink)
        .padding(.horizontal, 20)
        .background(PageStyle.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                }
                Spacer()
                Text(displayedCalendarDate.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 40, height: 40)
                }
            }
            .font(.system(size: 14, weight: .medium))

            GeometryReader { geometry in
                Color.clear
                    .overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(-1...1, id: \.self) { weekOffset in
                                if let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) {
                                    weekDays(starting: start)
                                        .frame(width: geometry.size.width)
                                }
                            }
                        }
                        .frame(width: geometry.size.width * 3, height: geometry.size.height)
                        .offset(x: -geometry.size.width + weekDragOffset)
                    }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .clipped()
                .highPriorityGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            guard !isWeekSettling, abs(value.translation.width) > abs(value.translation.height) else { return }
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                weekDragOffset = min(max(value.translation.width, -geometry.size.width), geometry.size.width)
                            }
                        }
                        .onEnded { value in
                            guard !isWeekSettling else { return }
                            let horizontal = value.translation.width
                            let direction = abs(horizontal) > abs(value.translation.height) && abs(horizontal) > geometry.size.width * 0.25 ? (horizontal < 0 ? 1 : -1) : 0
                            isWeekSettling = true
                            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88), completionCriteria: .removed) {
                                weekDragOffset = CGFloat(-direction) * geometry.size.width
                            } completion: {
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    if direction != 0, let day = calendar.date(byAdding: .weekOfYear, value: direction, to: displayedCalendarDate) {
                                        displayedCalendarDate = day
                                    }
                                    weekDragOffset = 0
                                    isWeekSettling = false
                                }
                            }
                        }
                )
            }
            .frame(height: 64)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func weekDays(starting start: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                    Button { selectDate(day) } label: {
                        VStack(spacing: 8) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PageStyle.muted)
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? ThemePalette.onAccent : PageStyle.ink)
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

    private func moveMonth(_ offset: Int) {
        guard !isWeekSettling,
              let monthStart = calendar.dateInterval(of: .month, for: displayedCalendarDate)?.start,
              let targetMonth = calendar.date(byAdding: .month, value: offset, to: monthStart),
              let validDays = calendar.range(of: .day, in: .month, for: targetMonth),
              let day = calendar.date(byAdding: .day, value: min(calendar.component(.day, from: displayedCalendarDate), validDays.count) - 1, to: targetMonth) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            weekDragOffset = 0
            displayedCalendarDate = day
        }
    }

    private func selectDate(_ date: Date, animated: Bool = true) {
        let day = calendar.startOfDay(for: date)
        guard day != selectedDate else { return }
        focusedInput = nil
        dayTransitionDirection = day > selectedDate ? 1 : -1
        let update = {
            selectedDate = day
            displayedCalendarDate = day
            expandedExerciseID = nil
            pendingScrollSetID = nil
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.2), update)
        } else {
            update()
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

    private func exerciseCardBackground(top: Bool, bottom: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: top ? 21 : 0,
            bottomLeadingRadius: bottom ? 21 : 0,
            bottomTrailingRadius: bottom ? 21 : 0,
            topTrailingRadius: top ? 21 : 0
        )
        .fill(ThemePalette.surface)
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
        case .weightReps:
            let heaviest = recorded.max {
                $0.weight == $1.weight ? $0.repetitions < $1.repetitions : $0.weight < $1.weight
            } ?? last
            result = "\(heaviest.weight.formatted()) кг × \(heaviest.repetitions)"
        case .reps: result = "\(recorded.map(\.repetitions).max() ?? last.repetitions) повт."
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
        let newSet = SetEntry()
        current.exercises[index].sets.append(newSet)
        store.upsert(current)
        pendingScrollSetID = newSet.id
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

private enum InsightEvidenceSelection: Identifiable {
    case insight(PersonalInsight, MuscleAnalysisSnapshot)
    case recommendation(TrainingRecommendation)

    var id: String {
        switch self {
        case .insight(let insight, _): "insight-\(insight.id)"
        case .recommendation(let recommendation): "recommendation-\(recommendation.id)"
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period: StatsPeriod = .month
    @State private var selectedEvidence: InsightEvidenceSelection?
    @State private var showingActiveWeeks = false

    private var analysis: MuscleAnalysisSnapshot {
        MuscleAnalysisEngine.analyze(store: store, period: period)
    }

    var body: some View {
        let snapshot = analysis
        let report = InsightsEngine.personalInsights(from: snapshot)
        let progressInsight = report.insights.first { $0.category == .progress || $0.category == .achievement }
        let visibleInsights = report.insights.filter { $0.id == report.insights.first?.id || $0.id == progressInsight?.id }
        let recommendations = RecommendationEngine.recommendations(
            analysis: snapshot,
            insights: PersonalInsightsResult(readiness: report.readiness,
                                             observationCount: report.observationCount,
                                             insights: visibleInsights))
        let hasInsight = report.readiness != .collecting && report.readiness != .insufficientData && !report.insights.isEmpty
        let hasAnalysis = report.readiness == .preliminary || report.readiness == .detailed
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Период анализа", selection: $period) {
                        ForEach(StatsPeriod.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(periodLabel(snapshot.period))
                        .font(.subheadline)
                        .foregroundStyle(PageStyle.muted)
                }

                heroCard(snapshot: snapshot, featured: hasInsight ? report.insights.first : nil)

                Text("Анализ тренировок")
                    .font(.headline)

                VStack(spacing: 8) {
                    NavigationLink {
                        MuscleStructureView(period: period)
                    } label: {
                        detailCard(title: "Мышечная структура", symbol: "figure.strengthtraining.traditional",
                                   subtitle: muscleSubtitle(snapshot: snapshot, hasAnalysis: hasAnalysis))
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ExerciseAnalysisView(period: period)
                    } label: {
                        detailCard(title: "Прогресс", symbol: "chart.line.uptrend.xyaxis",
                                   subtitle: hasAnalysis ? "Динамика результатов упражнений"
                                       : "Динамика результатов")
                    }
                    .buttonStyle(.plain)
                }

                if !recommendations.isEmpty {
                    Text("На что обратить внимание")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 4)
                    ForEach(recommendations) { recommendation in
                        Button {
                            selectedEvidence = .recommendation(recommendation)
                        } label: {
                            detailCard(title: recommendation.title, symbol: "lightbulb",
                                       subtitle: recommendation.explanation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .floatingTabBarClearance()
        .background(PageStyle.canvas.ignoresSafeArea())
        .foregroundStyle(PageStyle.ink)
        .navigationTitle("Инсайты")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEvidence) { selection in
            switch selection {
            case .insight(let insight, let snapshot):
                RecommendationDetailView(insight: insight, analysis: snapshot, period: period)
            case .recommendation(let recommendation):
                RecommendationDetailView(recommendation: recommendation, period: period)
            }
        }
        .sheet(isPresented: $showingActiveWeeks) {
            ActiveWeeksSheet(currentStreak: snapshot.regularity.consecutiveActiveWeeks)
        }
    }

    private func heroCard(snapshot: MuscleAnalysisSnapshot, featured: PersonalInsight?) -> some View {
        let metricsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(featured?.title ?? (snapshot.readiness == .preliminary || snapshot.readiness == .detailed
                    ? "Пока нет подтверждённых наблюдений" : snapshot.readiness == .insufficientData
                    ? "Нужно больше тренировочных дней" : "Собираем историю тренировок"))
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let featured {
                    Button("Подробнее") {
                        selectedEvidence = .insight(featured, snapshot)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PageStyle.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(ThemePalette.soft, in: Capsule())
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Text(readinessTitle(snapshot.readiness))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PageStyle.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(ThemePalette.soft, in: Capsule())
                }
            }
            Text(featured?.explanation ?? (snapshot.readiness == .preliminary || snapshot.readiness == .detailed
                ? "Для персональных выводов пока не хватает сопоставимых результатов."
                : snapshot.readiness == .insufficientData
                ? "История уже достаточна по времени, но в выбранном периоде нужны результаты минимум за два тренировочных дня."
                : snapshot.observationCount == 0 && snapshot.historyAgeDays == 0
                ? "Запишите первую тренировку с результатами, чтобы начать собирать историю."
                : "Первые наблюдения доступны после семи календарных дней истории и тренировок в разные дни."))
                .font(.footnote)
                .foregroundStyle(PageStyle.muted)
                .fixedSize(horizontal: false, vertical: true)

            metricsLayout {
                metricCard(value: "\(snapshot.regularity.workoutCount)", title: "Тренировки", symbol: "dumbbell")
                metricCard(value: snapshot.historyAgeDays == 0 && snapshot.observationCount == 0 ? "—" : "\(snapshot.historyAgeDays)", title: "Дней с первой записи", symbol: "calendar")
                Button { showingActiveWeeks = true } label: {
                    metricCard(value: "\(snapshot.regularity.consecutiveActiveWeeks)", title: "Серия недель", symbol: "chart.bar")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Серия активных недель: \(snapshot.regularity.consecutiveActiveWeeks). Подробнее")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 27))
        .shadow(color: .black.opacity(0.055), radius: 19, y: 8)
        .shadow(color: .black.opacity(0.025), radius: 3, y: 1)
    }

    private func readinessTitle(_ readiness: MuscleAnalysisReadiness) -> String {
        switch readiness {
        case .collecting: "Сбор истории"
        case .insufficientData: "Мало записей"
        case .preliminary: "Предварительно"
        case .detailed: "Подробно"
        }
    }

    private func metricCard(value: String, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PageStyle.muted)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 53, alignment: .topLeading)
        .padding(8)
        .background(ThemePalette.raised, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
    }

    private func detailCard(title: String, symbol: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 46, height: 46)
                .background(ThemePalette.soft, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PageStyle.ink)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(PageStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PageStyle.muted)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 13, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private func muscleSubtitle(snapshot: MuscleAnalysisSnapshot, hasAnalysis: Bool) -> String {
        guard hasAnalysis else { return "Группы мышц и подходы" }
        let groups = snapshot.groups.filter { $0.directSets > 0 }
        guard let leading = groups.max(by: { $0.directSets < $1.directSets }) else {
            return "Пока нет записанных силовых подходов за период"
        }
        return "Больше всего прямых подходов: \(leading.target.category.rawValue) — \(leading.directSets)"
    }

    private func periodLabel(_ interval: DateInterval) -> String {
        "\(interval.start.formatted(date: .abbreviated, time: .omitted)) — \(insightDisplayEnd(interval).formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct ActiveWeeksSheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWeek: Date?
    let currentStreak: Int

    private var calendar: Calendar { WorkoutStore.statisticsCalendar }

    private var weeks: [MuscleAnalysisWeek] {
        let workouts = store.workouts.filter { workout in
            workout.date <= .now && workout.exercises.contains { exercise in
                exercise.sets.contains { $0.hasRecordedResult(for: exercise.trackingType) }
            }
        }
        guard let first = workouts.map(\.date).min(),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first),
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        var result: [MuscleAnalysisWeek] = []
        var start = firstWeek.start
        while start <= currentWeek.start {
            let count = workouts.filter { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start == start }.count
            result.append(MuscleAnalysisWeek(start: start, workoutCount: count))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { break }
            start = next
        }
        return result
    }

    private var longestStreak: Int {
        var longest = 0
        var ongoing = 0
        for week in weeks {
            ongoing = week.isActive ? ongoing + 1 : 0
            longest = max(longest, ongoing)
        }
        return longest
    }

    var body: some View {
        let history = weeks
        let selected = history.first { $0.start == selectedWeek } ?? history.last
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    streakValue(currentStreak, title: "Текущая серия")
                    streakValue(longestStreak, title: "Самая длинная")
                }
                if history.isEmpty {
                    Text("Пока нет завершённых тренировок с записанными результатами.")
                        .font(.footnote)
                        .foregroundStyle(PageStyle.muted)
                } else {
                    Text("Недели · пн–вс")
                        .font(.footnote.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(history.reversed())) { week in
                                let isCurrentWeek = week.start == calendar.dateInterval(of: .weekOfYear, for: .now)?.start
                                Button { selectedWeek = week.start } label: {
                                    Text(week.start.formatted(.dateTime.day().month(.abbreviated)))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(week.isActive ? ThemePalette.onAccent : PageStyle.ink)
                                        .padding(.horizontal, 11)
                                        .frame(height: 36)
                                        .background(week.isActive ? PageStyle.ink : isCurrentWeek ? ThemePalette.surface : ThemePalette.soft,
                                                    in: RoundedRectangle(cornerRadius: 11))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 11)
                                                .stroke(selected?.start == week.start ? PageStyle.muted : isCurrentWeek ? ThemePalette.track : .clear, lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let selected,
                       let sunday = calendar.date(byAdding: .day, value: 6, to: selected.start) {
                        Text("\(selected.start.formatted(date: .abbreviated, time: .omitted)) — \(sunday.formatted(date: .abbreviated, time: .omitted)) · \(selected.workoutCount) тренировок")
                            .font(.footnote)
                            .foregroundStyle(PageStyle.muted)
                        if selected.start == calendar.dateInterval(of: .weekOfYear, for: .now)?.start && !selected.isActive {
                            Text("Текущая неделя ещё продолжается.")
                                .font(.footnote)
                                .foregroundStyle(PageStyle.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PageStyle.canvas.ignoresSafeArea())
            .navigationTitle("Серия активных недель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func streakValue(_ value: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(PageStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecommendationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    private let recommendation: TrainingRecommendation?
    private let insight: PersonalInsight?
    private let analysis: MuscleAnalysisSnapshot?
    private let basePeriod: DateInterval
    let period: StatsPeriod

    init(recommendation: TrainingRecommendation, period: StatsPeriod) {
        self.recommendation = recommendation
        self.insight = nil
        self.analysis = nil
        self.basePeriod = recommendation.period
        self.period = period
    }

    init(insight: PersonalInsight, analysis: MuscleAnalysisSnapshot, period: StatsPeriod) {
        self.recommendation = nil
        self.insight = insight
        self.analysis = analysis
        self.basePeriod = insight.period
        self.period = period
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text((recommendation?.category.label ?? insight?.category.label ?? "").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(PageStyle.muted)
                    if let recommendation {
                        Text(recommendation.title)
                            .font(.system(size: 21, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let previous = previousPeriod {
                            Text("Предыдущий период: \(periodLabel(previous))")
                        }
                        Text("\(previousPeriod == nil ? "Период" : "Текущий период"): \(periodLabel(evidencePeriod))")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(PageStyle.muted)
                    if let recommendation {
                        Text("\(observationLabel): \(recommendation.observationCount)")
                            .font(.system(size: 13))
                    }
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, evidence in
                        HStack {
                            Text(readableMetricName(evidence.name))
                            Spacer()
                            Text("\(evidence.value.formatted(.number.precision(.fractionLength(0...1)))) \(evidence.unit)")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))
                    }
                    if metrics.contains(where: { $0.unit == "кг" }) {
                        Text("Оценка силы на основе веса и повторений")
                            .font(.system(size: 12))
                            .foregroundStyle(PageStyle.muted)
                    }
                    if let action = recommendation?.action {
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
            .navigationTitle("Почему такой вывод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var metrics: [PersonalInsightMetric] {
        recommendation?.metrics ?? insight?.metrics ?? []
    }

    private var comparesPeriods: Bool {
        insight != nil && metrics.contains {
            ["В прошлом периоде", "Доля ранее", "Изменение в прошлом периоде"].contains($0.name)
        }
    }

    private var evidencePeriod: DateInterval {
        if comparesPeriods, let analysis { return analysis.period }
        return basePeriod
    }

    private var previousPeriod: DateInterval? {
        if comparesPeriods { return analysis?.previousPeriod }
        return recommendation?.previousPeriod
    }

    private var observationLabel: String {
        switch recommendation?.category {
        case .muscleAccents: "Подходов с участием группы"
        case .exerciseProgress: "Выполнений для тенденции"
        case .trainingDistribution: "Прямых подходов в сравнении"
        case .regularity: "Тренировок в сравнении"
        case nil: "Наблюдений"
        }
    }

    private func periodLabel(_ interval: DateInterval) -> String {
        "\(interval.start.formatted(date: .abbreviated, time: .omitted)) — \(insightDisplayEnd(interval).formatted(date: .abbreviated, time: .omitted))"
    }

    private func readableMetricName(_ name: String) -> String {
        switch name {
        case "Акценты с записанной работой": "Задействованные акценты"
        case "Прямые подходы": "Подходы с основным акцентом"
        case "Косвенные подходы": "Подходы с дополнительным участием"
        case "Всего сопоставимых выполнений": "Всего выполнений для сравнения"
        case "Доля сейчас": "Доля за этот период"
        case "Доля ранее": "Доля за прошлый период"
        case "Прямые подходы сейчас": "Основные подходы за период"
        case "В прошлом периоде": "За прошлый период"
        case "Тренировки сейчас": "Тренировки за период"
        default: name
        }
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
        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 16))
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
                        .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 16))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(period.rawValue) · результаты одного упражнения сравниваются только с его историей")
                    .font(.system(size: 13)).foregroundStyle(PageStyle.muted)
                if analysis.exercises.isEmpty {
                    Text("Для анализа динамики нужно больше сопоставимых тренировок.")
                        .font(.system(size: 14)).foregroundStyle(PageStyle.muted)
                        .padding(18)
                } else {
                    ForEach(analysis.exercises) { result in
                        NavigationLink {
                            ExerciseHistoryChartView(exerciseID: result.exerciseID, selectedDate: .now)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(result.name).font(.system(size: 17, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text("\(result.metric.label) · \(result.observationCount) наблюдений")
                                    .foregroundStyle(PageStyle.muted)
                                Text(trendTitle(result.trend, metric: result.metric))
                                    .font(.system(size: 14, weight: .semibold))
                                if result.canInferTrend {
                                    Chart {
                                        ForEach(result.recentValues.indices, id: \.self) { index in
                                            LineMark(x: .value("Выполнение", index + 1),
                                                     y: .value(result.metric.label, result.recentValues[index]))
                                                .foregroundStyle(PageStyle.ink)
                                            PointMark(x: .value("Выполнение", index + 1),
                                                      y: .value(result.metric.label, result.recentValues[index]))
                                                .foregroundStyle(PageStyle.ink)
                                        }
                                    }
                                    .chartXAxis(.hidden)
                                    .chartYAxis(.hidden)
                                    .frame(height: 42)
                                    .accessibilityHidden(true)
                                }
                                Text(trendExplanation(result))
                                    .foregroundStyle(PageStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(PageStyle.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(ThemePalette.surface, in: RoundedRectangle(cornerRadius: 16))
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

    private func trendTitle(_ trend: ExerciseResultTrend, metric: ExerciseResultMetric) -> String {
        switch trend {
        case .improvement: "Положительная динамика"
        case .stable: "Стабильная динамика"
        case .decline: "Результаты снизились"
        case .changed: metric == .cardioDurationSeconds || metric == .cardioDistanceKilometers
            ? "Изменение результата" : "Неоднозначная динамика"
        case .insufficientData: "Тенденция пока не определена"
        }
    }

    private func trendExplanation(_ result: ExerciseProgressResult) -> String {
        switch result.trend {
        case .improvement: "За последние пять сопоставимых выполнений результат в целом вырос."
        case .stable: result.hasIdenticalRecentResults
            ? "Пять последних сопоставимых результатов совпадают."
            : "Пять последних сопоставимых результатов близки, с небольшими колебаниями."
        case .decline: "За последние пять сопоставимых выполнений результат в целом снизился; причина неизвестна."
        case .changed: result.metric == .cardioDurationSeconds || result.metric == .cardioDistanceKilometers
            ? "Длительность и дистанция описывают занятия, но сами по себе не показывают улучшение формы."
            : "Результаты колебались без устойчивого направления."
        case .insufficientData: "Для анализа динамики нужно не менее пяти сопоставимых выполнений."
        }
    }
}

private extension ExerciseResultMetric {
    var label: String {
        switch self {
        case .estimatedOneRepMax: "Оценка силы"
        case .repetitions: "Повторения"
        case .durationSeconds, .cardioDurationSeconds: "Длительность"
        case .cardioDistanceKilometers: "Дистанция"
        }
    }
    var unit: String {
        switch self {
        case .estimatedOneRepMax: "кг"
        case .repetitions: "повт."
        case .durationSeconds, .cardioDurationSeconds: "сек."
        case .cardioDistanceKilometers: "км"
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    #if DEBUG
    @AppStorage("debugDemoMode") private var debugDemoMode = false
    #endif

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
            Section("Внешний вид") {
                HStack(spacing: 2) {
                    ForEach(AppAppearance.allCases) { option in
                        Button {
                            appearance = option.rawValue
                        } label: {
                            Text(option.title)
                                .font(.system(size: 13, weight: appearance == option.rawValue ? .semibold : .regular))
                                .foregroundStyle(appearance == option.rawValue ? PageStyle.ink : PageStyle.muted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(appearance == option.rawValue ? ThemePalette.surface : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance == option.rawValue ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(ThemePalette.soft, in: Capsule())
            }
            #if DEBUG
            Section {
                Toggle("Демонстрационная история", isOn: $debugDemoMode)
            } footer: {
                Text("Только DEBUG. Данные хранятся отдельно в памяти и не меняют ваши тренировки.")
            }
            #endif
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
                            .tint(.red)
                            .foregroundStyle(.white)
                            .buttonStyle(.automatic)
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
