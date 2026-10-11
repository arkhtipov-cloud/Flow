import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let muted = Color(red: 0.59, green: 0.59, blue: 0.61)
    static let canvas = Color(red: 0.985, green: 0.985, blue: 0.988)
    static let surface = Color.white
    static let soft = Color(red: 0.955, green: 0.955, blue: 0.96)
}

struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Binding var selectedTab: MainTab
    @State private var destination: HomeDestination?
    @State private var period: StatsPeriod = .week
    private let horizontalPadding: CGFloat = 18

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                quickAccess
                streakCard
                weeklyCard
                statisticsCard
                insightCard
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 20)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .insights: InsightsView()
            case .settings: SettingsView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: -2) {
                Text("GymTreker")
                    .font(.system(size: 39, weight: .bold, design: .default))
                    .tracking(-1.3)
                    .foregroundStyle(Palette.ink)
                Text("Всё под контролем")
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { destination = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 49, height: 49)
                    .background(Palette.soft, in: Circle())
            }
            .accessibilityLabel("Настройки")
        }
    }

    private var quickAccess: some View {
        Button { selectedTab = .workouts } label: {
            HStack {
                Text("Перейти к тренировкам")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(PressableCardStyle())
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Серия недель")
                .font(.system(size: 16, weight: .semibold))
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                Text("\(store.streakWeeks)")
                    .font(.system(size: 29, weight: .bold))
                Text("нед.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { index in
                        Circle()
                            .fill(index < min(store.streakWeeks, 7) ? Palette.ink : Palette.soft)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 17)
        .frame(height: 79)
        .cardSurface()
    }

    private var weeklyCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Прогресс недели")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(store.thisWeekCount) из \(store.weeklyGoal) тренировок")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 2)
            HStack(spacing: store.weeklyGoal > 5 ? 4 : 7) {
                ForEach(0..<store.weeklyGoal, id: \.self) { index in
                    WeekProgressRing(style: index < store.thisWeekCount ? .complete : .empty)
                }
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 64)
        .cardSurface()
    }

    private var statisticsCard: some View {
        let snapshot = store.snapshot(for: period)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Статистика")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }

            HStack(spacing: 3) {
                ForEach(StatsPeriod.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { period = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 13, weight: period == option ? .semibold : .regular))
                            .foregroundStyle(period == option ? Palette.ink : Palette.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(period == option ? Color.white : Color.clear, in: Capsule())
                    }
                    .accessibilityAddTraits(period == option ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Palette.soft, in: Capsule())

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(snapshot.buckets) { bucket in
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(bucket.count > 0 ? Palette.ink : Color(white: 0.85))
                            .frame(width: period == .year ? 7 : 9, height: CGFloat(max(8, min(49, bucket.count * 21))))
                            .frame(height: 43, alignment: .bottom)
                        Text(bucket.label)
                            .font(.system(size: 10))
                            .foregroundStyle(bucket.count > 0 ? Palette.ink : Palette.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 0) {
                metric(value: "\(snapshot.workoutCount)", label: "Тренировки", symbol: "dumbbell")
                metric(value: "\(snapshot.exerciseCount)", label: "Упражнения", symbol: "list.bullet")
            }
        }
        .padding(13)
        .cardSurface()
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .background(Palette.soft, in: Circle())
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity)
    }

    private var insightCard: some View {
        let insight = InsightsEngine.snapshot(workouts: store.workouts, definitions: store.exercises).featured
        return Button { destination = .insights } label: {
            HStack(spacing: 12) {
                Image(systemName: insight?.symbol ?? "sparkle.magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Palette.soft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Инсайт")
                        .font(.system(size: 16, weight: .semibold))
                    Text(insight.map { "\($0.title) · \($0.message)" } ?? "Здесь появятся инсайты после нескольких тренировок")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                    if let insight {
                        Text(insight.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
            .cardSurface()
        }
        .buttonStyle(PressableCardStyle())
    }
}

private enum HomeDestination: Hashable, Identifiable {
    case insights, settings
    var id: Self { self }
}

private struct WeekProgressRing: View {
    enum Style { case complete, empty }
    let style: Style

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.88), lineWidth: 5)
            if style == .complete {
                Circle().fill(Palette.ink).padding(5)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 31, height: 31)
        .accessibilityLabel(style == .complete ? "Выполнено" : "Не выполнено")
    }
}

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 15, y: 5)
    }
}

private extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
