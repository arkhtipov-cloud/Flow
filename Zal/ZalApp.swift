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
    @State private var selectedTab: MainTab = .statistics
    @State private var showingStorageError = false
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
            .environmentObject(store)
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
            .tint(ThemePalette.ink)
            .onReceive(store.$saveError) { showingStorageError = $0 != nil }
            .alert("Ошибка хранилища", isPresented: $showingStorageError) {
                Button("Понятно", role: .cancel) { }
            } message: {
                Text(store.saveError ?? "Изменения не сохранены.")
            }
        }
    }
}
