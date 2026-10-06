import SwiftUI
import NutritionCore

struct PremiumEnergyCard: View {
    let budget: DayBudget
    let baseTitle: String
    let goal: String
    let isToday: Bool
    let edit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var fraction: Double { min(max(budget.eaten / max(budget.target, 1), 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label(goal, systemImage: "leaf")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(action: edit) {
                    HStack(spacing: 6) { Text("Цель и норма"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(Palette.surface.opacity(0.5), in: Capsule())
                }.buttonStyle(.plain).modifier(HoverLift())
            }
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(budget.remaining >= 0 ? "Осталось на \(isToday ? "сегодня" : "этот день")" : "Сверх дневного ориентира")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(Numbers.display(abs(budget.remaining), decimals: 0))
                            .font(.system(size: 72, weight: .semibold, design: .rounded)).tracking(-3)
                            .monospacedDigit().animatedNumber(abs(budget.remaining))
                            .lineLimit(1).minimumScaleFactor(0.55)
                        Text("ккал").font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.secondary)
                    }
                    Text("из \(Numbers.display(budget.target, decimals: 0)) ккал · дневной ориентир")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    if budget.awaitingActivity {
                        Label(budget.provisionalActivity > 0 ? "Данных часов пока нет · учтена минимальная бытовая активность" : "Пока без активности с часов", systemImage: "clock")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(Palette.green.opacity(0.09), lineWidth: 16)
                    Circle().trim(from: 0, to: appeared || reduceMotion ? fraction : 0)
                        .stroke(AngularGradient(colors: [Color(red: 0.42, green: 0.82, blue: 0.70), Palette.green], center: .center),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Palette.green.opacity(0.22), radius: 6, y: 3)
                        .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.86), value: appeared)
                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: fraction)
                    Circle().stroke(Palette.edge.opacity(0.9), lineWidth: 1).padding(14)
                    VStack(spacing: 6) {
                        Image(systemName: "fork.knife").font(.system(size: 18, weight: .light)).foregroundStyle(Palette.green)
                        Text("\(Numbers.display(budget.eaten / max(budget.target, 1) * 100, decimals: 0))%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("съедено").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }.frame(width: 162, height: 162).padding(10)
                    .accessibilityElement(children: .combine)
            }
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
            HStack(spacing: 16) {
                metric(baseTitle, value: budget.base, sign: "", symbol: "heart", color: Palette.gold)
                if budget.creditsActivity {
                    let estimated = budget.active == nil && budget.provisionalActivity > 0
                    metric(estimated ? "Активность ≈" : "Активность", value: estimated ? budget.provisionalActivity : budget.active,
                           sign: "+", symbol: "figure.walk", color: Palette.blue)
                }
                metric("Съедено", value: budget.eaten, sign: "−", symbol: "fork.knife", color: Palette.green)
            }
            if budget.deficit > 0 || !isToday {
                HStack(alignment: .top) {
                    if budget.deficit > 0 {
                        Text("Дефицит \(Numbers.display(budget.deficit, decimals: 0)) ккал уже учтён")
                    }
                    Spacer(minLength: 12)
                    if !isToday { Text("Норма по текущим параметрам") }
                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }.padding(27).foregroundStyle(Palette.ink)
            .liquidSurface(radius: 30, tint: Palette.surface.opacity(0.22), clear: true)
            .onAppear { appeared = true }
    }
    private func metric(_ name: String, value: Double?, sign: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(value.map { ($0 > 0 ? sign : "") + Numbers.display($0, decimals: 0) } ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65).animatedNumber(value ?? 0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
