import SwiftUI

enum MainTab: Hashable {
    case statistics
    case workouts
}

@main
struct ZalApp: App {
    @StateObject private var store = WorkoutStore()
    @State private var selectedTab: MainTab = .statistics

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
            .preferredColorScheme(.light)
            .tint(.black)
        }
    }
}
