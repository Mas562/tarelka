import SwiftUI
import NutritionCore

struct MenuBarDashboard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var personal: PersonalStore
    @Environment(\.openWindow) private var openWindow

    private let ink = Color(red: 0.96, green: 0.98, blue: 1.00)
    private let muted = Color(red: 0.72, green: 0.79, blue: 0.86)
    private let mint = Color(red: 0.49, green: 0.90, blue: 0.78)
    private let panel = Color(red: 0.18, green: 0.25, blue: 0.36)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let eaten = model.total(on: timeline.date)
            let budget = personal.data.budget(on: timeline.date, eaten: eaten.calories)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.08, green: 0.19, blue: 0.25))
                        .frame(width: 38, height: 38)
                        .background(mint, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Тарелка")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)
                        Text("Сегодня · \(model.meals(on: timeline.date).count) записей")
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Button { show(.day) } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Открыть мой день")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(budget == nil ? "СЪЕДЕНО СЕГОДНЯ" : "ОСТАЛОСЬ НА СЕГОДНЯ")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.25)
                        .foregroundStyle(muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Numbers.display(budget?.remaining ?? eaten.calories, decimals: 0))
                            .font(.system(size: 37, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                        Text("ккал")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(muted)
                    }
                    if let budget {
                        Text("Съедено \(Numbers.display(eaten.calories, decimals: 0)) · цель \(Numbers.display(budget.target, decimals: 0))")
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                        if budget.creditsActivity {
                            Label(budget.awaitingActivity ? "Ожидаем данные часов" : "+\(Numbers.display(budget.creditedActivity, decimals: 0)) ккал активности",
                                  systemImage: "figure.run")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(mint)
                        }
                    } else {
                        Text("Задайте дневной ориентир в приложении")
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.11)))

                HStack(spacing: 7) {
                    macro("Б", eaten.protein, budget?.macroTargets?.protein, Color(red: 0.51, green: 0.75, blue: 1))
                    macro("Ж", eaten.fat, budget?.macroTargets?.fat, Color(red: 1, green: 0.76, blue: 0.52))
                    macro("У", eaten.carbs, budget?.macroTargets?.carbs, mint)
                }

                HStack(spacing: 8) {
                    Button { model.drinkEditor = DrinkDraft(); showWindow() } label: {
                        Label("Напиток", systemImage: "cup.and.saucer.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 35)
                            .foregroundStyle(Color(red: 0.08, green: 0.19, blue: 0.25))
                            .background(mint, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    Button { show(.newMeal) } label: {
                        Label("Блюдо", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .frame(height: 35)
                            .foregroundStyle(ink)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.13)))
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, weight: .semibold))

                if !model.recentMeals.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ПОВТОРИТЬ НЕДАВНЕЕ")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(muted)
                            .padding(.bottom, 3)
                        ForEach(model.recentMeals.prefix(3)) { meal in
                            Button { model.repeatMeal(meal) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: meal.isDrink ? "cup.and.saucer" : "fork.knife")
                                        .foregroundStyle(mint)
                                        .frame(width: 17)
                                    Text(meal.name)
                                        .foregroundStyle(ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(Numbers.display(meal.total.calories, decimals: 0)) ккал")
                                        .foregroundStyle(muted)
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(mint)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                            .help("Добавить такую же порцию в сегодняшний дневник")
                        }
                    }
                }

                Button { show(.diary) } label: {
                    HStack {
                        Text("Открыть дневник")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mint)
                }
                .buttonStyle(.plain)
            }
            .padding(17)
            .frame(width: 330)
            .background {
                LinearGradient(colors: [Color(red: 0.11, green: 0.17, blue: 0.27),
                                        Color(red: 0.08, green: 0.15, blue: 0.23)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private func macro(_ name: String, _ eaten: Double, _ target: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name).font(.system(size: 10, weight: .bold)).foregroundStyle(muted)
            }
            Text("\(Numbers.display(target.map { max(0, $0 - eaten) } ?? eaten, decimals: 0)) г")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
            Text(target == nil ? "съедено" : "осталось")
                .font(.system(size: 9))
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    private func show(_ screen: Screen) { model.screen = screen; showWindow() }
    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
