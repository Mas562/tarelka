import SwiftUI
import NutritionCore

struct DailyMacrosCard: View {
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eaten: Nutrients
    let budget: DayBudget?
    let editProfile: () -> Void

    var body: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 19) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Баланс БЖУ").font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                    Spacer()
                    Text("ОСТАТОК НА ДЕНЬ").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.secondary)
                }
                HStack(alignment: .top, spacing: 18) {
                    column("Белки", eaten: eaten.protein, target: budget?.macroTargets?.protein, color: Color(red: 0.06, green: 0.49, blue: 0.46))
                    column("Жиры", eaten: eaten.fat, target: budget?.macroTargets?.fat, color: Palette.orange)
                    column("Углеводы", eaten: eaten.carbs, target: budget?.macroTargets?.carbs, color: Palette.violet)
                }
                if budget?.macroTargets == nil {
                    Button("Рассчитать ориентиры по моим параметрам", action: editProfile).buttonStyle(SoftButton())
                } else {
                    if budget?.awaitingActivity == true {
                        Text("Пока без активности: с данными часов ориентиры обновятся.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    MacroMethodDetails()
                    if let budget, let hint = MacroHint.make(eaten: eaten, budget: budget,
                        hasPreferences: !(personal.data.dietaryNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(hint.title, systemImage: "lightbulb").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.green)
                            Text(hint.message).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            Text("По записям выбранного дня")
                                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.mint.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func column(_ title: String, eaten: Double, target: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label { Text(title) } icon: { Circle().fill(color).frame(width: 6, height: 6) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
            if let target {
                let progress = MacroProgress(eaten: eaten, target: target)
                Text("\(Numbers.display(progress.excess > 0 ? progress.excess : progress.remaining)) г")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).animatedNumber(progress.excess > 0 ? progress.excess : progress.remaining)
                Text(progress.excess > 0 ? "выше ориентира" : "осталось до ориентира")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * progress.fraction)
                    }
                }.frame(height: 5).padding(.vertical, 5)
                    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9), value: progress.fraction)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title): съедено \(Numbers.display(eaten)) из \(Numbers.display(target)) г")
                    .accessibilityValue("\(Numbers.display(progress.fraction * 100, decimals: 0)) процентов")
                Text("Съедено \(Numbers.display(eaten)) г")
                    .font(.system(size: 12, weight: .medium))
                Text("Ориентир ≈ \(Numbers.display(target)) г")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)

            } else {
                Text("\(Numbers.display(eaten)) г").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(color)
                Text("съедено · ориентир не задан").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.07)))
    }
}

struct MacroTargetSummary: View {
    let targets: MacroTargets
    var body: some View {
        HStack(spacing: 16) {
            value("Белки", grams: targets.protein, color: Palette.green)
            value("Жиры", grams: targets.fat, color: Palette.orange)
            value("Углеводы", grams: targets.carbs, color: Palette.blue)
        }
    }
    private func value(_ name: String, grams: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Text("≈ \(Numbers.display(grams)) г").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).animatedNumber(grams)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacroMethodDetails: View {
    var body: some View {
        DisclosureGroup("Как рассчитаны БЖУ") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Рост, вес, возраст и пол учитываются через норму калорий. Для БЖУ приложение распределяет энергию дня: 20% на белки, 30% на жиры и 50% на углеводы. В 1 г белков и углеводов — 4 ккал, жиров — 9 ккал.")
                Text("Используется дневной ориентир с учётом выбранной цели и активности. Если база введена вручную, расчёт идёт от неё. Это ориентиры для планирования, а не жёсткие пределы: добирать каждый грамм не обязательно.")
                Link("Рекомендуемые диапазоны для взрослых · National Academies", destination: URL(string: "https://www.nationalacademies.org/read/10925/chapter/25")!)
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
    }
}
