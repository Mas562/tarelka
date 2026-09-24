import SwiftUI
import NutritionCore

struct MenuBarDashboard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var personal: PersonalStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let eaten = model.total(on: timeline.date)
            let budget = personal.data.budget(on: timeline.date, eaten: eaten.calories)
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: "fork.knife").font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Тарелка").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("Сегодня · \(model.meals(on: timeline.date).count) записей")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { show(.day) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.plain).accessibilityLabel("Открыть мой день")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(budget == nil ? "СЪЕДЕНО" : "ОСТАЛОСЬ НА СЕГОДНЯ")
                        .font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Numbers.display(budget?.remaining ?? eaten.calories, decimals: 0))
                            .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("ккал").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if let budget {
                        Text("Съедено \(Numbers.display(eaten.calories, decimals: 0)) · цель \(Numbers.display(budget.target, decimals: 0))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if budget.creditsActivity {
                            Text(budget.awaitingActivity ? "Ожидаем данные часов" : "+\(Numbers.display(budget.creditedActivity, decimals: 0)) ккал активности")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Задайте дневной ориентир в приложении")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 19))
                HStack(spacing: 7) {
                    macro("Б", eaten.protein, budget?.macroTargets?.protein, .blue)
                    macro("Ж", eaten.fat, budget?.macroTargets?.fat, .orange)
                    macro("У", eaten.carbs, budget?.macroTargets?.carbs, .mint)
                }
                HStack(spacing: 8) {
                    Button { model.drinkEditor = DrinkDraft(); showWindow() } label: {
                        Label("Напиток", systemImage: "cup.and.saucer.fill")
                    }.buttonStyle(.borderedProminent)
                    Button { show(.newMeal) } label: { Label("Новое блюдо", systemImage: "plus") }
                        .buttonStyle(.bordered)
                }
                if !model.recentMeals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ПОВТОРИТЬ НЕДАВНЕЕ").font(.system(size: 10, weight: .bold))
                            .tracking(1.2).foregroundStyle(.secondary)
                        ForEach(model.recentMeals) { meal in
                            Button { model.repeatMeal(meal) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: meal.isDrink ? "cup.and.saucer" : "fork.knife")
                                        .frame(width: 18)
                                    Text(meal.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(Numbers.display(meal.total.calories, decimals: 0)) ккал")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "plus.circle.fill")
                                }.font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                                .help("Добавить такую же порцию в сегодняшний дневник")
                        }
                    }
                }
                Button("Открыть дневник") { show(.diary) }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }.padding(17).frame(width: 330)
                .background {
                    LinearGradient(colors: [Color(red: 0.85, green: 0.94, blue: 1),
                                            Color(red: 0.94, green: 0.92, blue: 1),
                                            Color(red: 0.91, green: 0.99, blue: 0.97)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
    }

    private func macro(_ name: String, _ eaten: Double, _ target: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name).font(.system(size: 10, weight: .bold))
            }
            Text("\(Numbers.display(target.map { max(0, $0 - eaten) } ?? eaten, decimals: 0)) г")
                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(target == nil ? "съедено" : "осталось").font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
    }
    private func show(_ screen: Screen) { model.screen = screen; showWindow() }
    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
