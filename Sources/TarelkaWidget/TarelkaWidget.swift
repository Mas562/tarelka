import SwiftUI
import WidgetKit
import NutritionCore

private struct BalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot?
}

private struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry { BalanceEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(BalanceEntry(date: .now, snapshot: TodaySnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let now = Date()
        let nextDay = Calendar.current.date(byAdding: .day, value: 1,
                                           to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: [BalanceEntry(date: now, snapshot: TodaySnapshotStore.load(on: now))],
                            policy: .after(min(now.addingTimeInterval(900), nextDay))))
    }
}

private struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalanceEntry
    private let blue = Color(red: 0.12, green: 0.40, blue: 0.79)
    private let ink = Color(red: 0.11, green: 0.17, blue: 0.27)

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            HStack(spacing: 7) {
                Image(systemName: "fork.knife").font(.system(size: 13, weight: .bold))
                    .frame(width: 29, height: 29)
                    .background(blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Тарелка").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(blue)
            }
            if let snapshot = entry.snapshot {
                Text(snapshot.remaining == nil ? "Съедено сегодня" : "Осталось на сегодня")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Numbers.display(snapshot.remaining ?? snapshot.eaten.calories, decimals: 0))
                        .font(.system(size: family == .systemSmall ? 30 : 35,
                                      weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("ккал").font(.system(size: 11)).foregroundStyle(.secondary)
                }.lineLimit(1).minimumScaleFactor(0.7)
                if family != .systemSmall {
                    HStack(spacing: 6) {
                        macro("Б", snapshot.eaten.protein, snapshot.macroTargets?.protein, .blue)
                        macro("Ж", snapshot.eaten.fat, snapshot.macroTargets?.fat, .orange)
                        macro("У", snapshot.eaten.carbs, snapshot.macroTargets?.carbs, .teal)
                    }
                } else {
                    let targets = snapshot.macroTargets
                    Text("Б \(number(targets.map { max(0, $0.protein - snapshot.eaten.protein) } ?? snapshot.eaten.protein)) · Ж \(number(targets.map { max(0, $0.fat - snapshot.eaten.fat) } ?? snapshot.eaten.fat)) · У \(number(targets.map { max(0, $0.carbs - snapshot.eaten.carbs) } ?? snapshot.eaten.carbs)) г")
                        .font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text("\(snapshot.entryCount) записей · \(number(snapshot.eaten.calories)) съедено")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Spacer(minLength: 0)
                Text("Откройте Тарелку")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("Баланс появится после запуска приложения")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.padding(family == .systemSmall ? 13 : 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(ink)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [.white, Color(red: 0.90, green: 0.96, blue: 1),
                                        Color(red: 0.91, green: 0.94, blue: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "tarelka://day"))
            .accessibilityElement(children: .combine)
    }

    private func macro(_ label: String, _ eaten: Double, _ target: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: 10, weight: .bold))
            }
            Text("\(number(target.map { max(0, $0 - eaten) } ?? eaten)) г")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(target == nil ? "съедено" : "осталось")
                .font(.system(size: 8)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func number(_ value: Double) -> String { Numbers.display(value, decimals: 0) }
}

@main
struct TarelkaTodayWidget: Widget {
    let kind = TodaySnapshotStore.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Баланс дня")
        .description("Остаток калорий и БЖУ из Тарелки.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
