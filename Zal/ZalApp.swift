import SwiftUI

enum MainTab: Hashable {
    case statistics
    case workouts
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ThemePalette {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    static let ink = adaptive(UIColor(white: 0.06, alpha: 1), UIColor(white: 0.96, alpha: 1))
    static let muted = adaptive(UIColor(white: 0.58, alpha: 1), UIColor(white: 0.66, alpha: 1))
    static let canvas = adaptive(UIColor(red: 0.985, green: 0.985, blue: 0.988, alpha: 1), UIColor(white: 0.075, alpha: 1))
    static let surface = adaptive(.white, UIColor(white: 0.13, alpha: 1))
    static let raised = adaptive(UIColor(white: 0.99, alpha: 1), UIColor(white: 0.17, alpha: 1))
    static let soft = adaptive(UIColor(red: 0.955, green: 0.955, blue: 0.96, alpha: 1), UIColor(white: 0.21, alpha: 1))
    static let track = adaptive(UIColor(white: 0.91, alpha: 1), UIColor(white: 0.27, alpha: 1))
    static let onAccent = adaptive(.white, UIColor(white: 0.075, alpha: 1))
}

@main
struct ZalApp: App {
    @StateObject private var store = WorkoutStore()
    #if DEBUG
    @StateObject private var demoStore = WorkoutStore(isEphemeral: true)
    @AppStorage("debugDemoMode") private var debugDemoMode = false
    #endif
    @State private var selectedTab: MainTab = .statistics
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(selectedTab: $selectedTab)
                }
                .tabItem {
                    Label("Статистика", systemImage: "chart.bar")
                }
                .tag(MainTab.statistics)

                NavigationStack {
                    WorkoutsTabView()
                }
                .tabItem {
                    Label("Тренировки", systemImage: "dumbbell")
                }
                .tag(MainTab.workouts)
            }
            .environmentObject(activeStore)
            #if DEBUG
            .id(debugDemoMode)
            .onAppear { if debugDemoMode { seedDemoIfNeeded() } }
            .onChange(of: debugDemoMode) { _, enabled in
                if enabled { seedDemoIfNeeded() }
                selectedTab = .statistics
            }
            #endif
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
            .tint(ThemePalette.ink)
        }
    }

    private var activeStore: WorkoutStore {
        #if DEBUG
        debugDemoMode ? demoStore : store
        #else
        store
        #endif
    }

    #if DEBUG
    private func seedDemoIfNeeded() {
        guard demoStore.records.isEmpty else { return }
        let names = [
            ["Жим штанги лёжа", "Жим гантелей лёжа", "Разгибание рук на блоке", "Приседания со штангой", "Жим ногами"],
            ["Тяга верхнего блока", "Тяга штанги к поясу", "Подъём гантелей на бицепс", "Приседания со штангой", "Жим ногами"],
            ["Жим штанги лёжа", "Тяга верхнего блока", "Подъём гантелей на бицепс", "Разгибание рук на блоке", "Жим гантелей лёжа"]
        ]
        let weights: [String: [Double]] = [
            "Жим штанги лёжа": [60, 62, 61, 64, 66, 65, 68, 70, 69, 72],
            "Жим гантелей лёжа": [22, 23, 22, 24, 25, 24, 26, 27, 26, 28],
            "Тяга верхнего блока": [50, 51, 50, 50, 51, 50, 51, 50, 50, 51],
            "Тяга штанги к поясу": [45, 50, 42, 51, 46],
            "Приседания со штангой": [70, 72, 71, 74, 76, 75, 78, 80, 79, 82],
            "Жим ногами": [140, 142, 140, 141, 142, 140, 141, 142, 140, 141],
            "Подъём гантелей на бицепс": [12, 13, 12, 14, 13, 14, 13, 15, 14, 15],
            "Разгибание рук на блоке": [25, 25, 26, 25, 26, 25, 26, 25, 26, 25]
        ]
        let definitions = Dictionary(uniqueKeysWithValues: demoStore.exercises.map { ($0.name, $0) })
        guard names.flatMap({ $0 }).allSatisfy({ definitions[$0] != nil }) else { return }
        let offsets = [-33, -31, -29, -26, -24, -22, -19, -17, -15, -12, -10, -8, -5, -3, -1]
        let today = Calendar.current.startOfDay(for: .now)
        var occurrences: [String: Int] = [:]
        for (session, offset) in offsets.enumerated() {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            let exercises = names[session % names.count].enumerated().compactMap { position, name -> WorkoutExercise? in
                guard let definition = definitions[name], let values = weights[name] else { return nil }
                let count = occurrences[name, default: 0]
                guard count < values.count else { return nil }
                occurrences[name] = count + 1
                let weight = values[count]
                let seed = 1000 + session * 100 + position * 10
                let sets = (0..<3).map { set in
                    SetEntry(id: demoUUID(seed + set), weight: weight - Double(set * 2), repetitions: 8)
                }
                return WorkoutExercise(id: demoUUID(100 + session * 10 + position), exerciseID: definition.id,
                                       name: definition.name, sets: sets, trackingType: definition.trackingType)
            }
            demoStore.upsert(WorkoutRecord(id: demoUUID(session + 1), title: "Демо · тренировка \(session + 1)",
                                           date: day.addingTimeInterval(18 * 3600), exercises: exercises))
        }
    }

    private func demoUUID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "D3A00000-0000-4000-8000-%012X", number))!
    }
    #endif
}
