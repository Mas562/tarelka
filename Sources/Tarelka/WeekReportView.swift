import SwiftUI
import Charts
import NutritionCore

struct WeekReportView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @State private var selectedDate = Date()
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        let report = WeekSummary(containing: selectedDate, meals: model.meals, personal: personal.data)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "Обзор питания")
                        Text("Ваша неделя").font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                    }
                    Spacer()
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 26, weight: .light)).foregroundStyle(Palette.green)
                        .frame(width: 58, height: 58).liquidSurface(radius: 19, tint: Palette.mint.opacity(0.4))
                }
                weekPicker(report)
                overview(report)
                caloriesChart(report)
                macros(report)
                dayList(report)
                Text("Отчёт отражает только записи в дневнике. Пропущенные дни не считаются нулевыми, а сегодняшний день ещё может быть неполным. Значения по фото остаются приблизительными.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(32).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
    }

    private func weekPicker(_ report: WeekSummary) -> some View {
        HStack(spacing: 13) {
            Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SoftButton()).accessibilityLabel("Предыдущая неделя")
            VStack(alignment: .leading, spacing: 3) {
                Text(dateRange(report)).font(.system(size: 16, weight: .semibold))
                Text("Понедельник — воскресенье").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SoftButton())
                .disabled(report.end > Date()).accessibilityLabel("Следующая неделя")
            Spacer()
            ModernDatePicker(title: "Выбрать неделю по дате", selection: $selectedDate, maximumDate: Date())
                .accessibilityLabel("Выбрать неделю по дате")
            Button("Эта неделя") { selectedDate = Date() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
        }
    }

    private func overview(_ report: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("СРЕДНЕЕ ЗА ДЕНЬ С ЗАПИСЯМИ").font(.system(size: 9, weight: .bold)).tracking(1.3)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(report.average.map { Numbers.display($0.calories, decimals: 0) } ?? "—")
                            .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("ккал").font(.system(size: 14)).opacity(0.75)
                    }
                    Text(report.loggedDays.isEmpty ? "Добавьте первую запись — и неделя оживёт." : "По \(report.loggedDays.count) дн. с записями · еда и напитки")
                        .font(.system(size: 11)).opacity(0.85)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(Array(report.days.enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 7) {
                                Image(systemName: day.hasEntries ? "checkmark" : day.isFuture ? "minus" : "circle")
                                    .font(.system(size: 10, weight: .semibold)).frame(width: 26, height: 31)
                                    .background(Palette.blue.opacity(day.hasEntries ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 9))
                                Text(weekdays[index]).font(.system(size: 9)).opacity(0.8)
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(weekdays[index]): \(day.hasEntries ? "есть записи" : day.isFuture ? "ещё впереди" : "нет записей")")
                        }
                    }
                    Text("Дней с записями: \(report.loggedDays.count) из \(report.elapsedDays)")
                        .font(.system(size: 10)).opacity(0.85)
                }
            }
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
            HStack(spacing: 20) {
                heroMetric("Записано за неделю", value: report.loggedDays.isEmpty ? "—" : "\(Numbers.display(report.total.calories, decimals: 0)) ккал", detail: "Записей: \(report.entryCount)", symbol: "fork.knife")
                heroMetric("Активные калории", value: report.totalActivity.map { "\(Numbers.display($0, decimals: 0)) ккал" } ?? "Нет данных", detail: "Данных по дням: \(report.activityDays.count) из \(report.elapsedDays)", symbol: "flame")
                heroMetric("Напитки", value: "\(Numbers.display(report.loggedDays.reduce(0) { $0 + $1.drinkMilliliters }, decimals: 0)) мл", detail: "Записей: \(report.drinkCount)", symbol: "cup.and.saucer")
            }
        }.foregroundStyle(Palette.ink).padding(25)
            .liquidSurface(radius: 26, tint: Palette.mint.opacity(0.08)).arrive(delay: 0.05)
    }

    private func heroMetric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 10)).opacity(0.8)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 9)).opacity(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caloriesChart(_ report: WeekSummary) -> some View {
        let ceiling = max(100, report.days.map { max($0.total.calories, $0.budget?.target ?? 0) }.max() ?? 0) * 1.15
        return Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Калории по дням").font(.system(size: 19, weight: .semibold))
                    Spacer()
                    Label("Съедено и выпито", systemImage: "circle.fill").foregroundStyle(Palette.green).font(.system(size: 10))
                }
                Chart {
                    ForEach(Array(report.days.enumerated()), id: \.offset) { index, day in
                        if day.hasEntries {
                            BarMark(x: .value("День", Double(index)), y: .value("Калории", day.total.calories), width: .fixed(36))
                                .foregroundStyle(LinearGradient(colors: [Palette.green, Palette.green.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(6)
                                .accessibilityLabel("\(weekdays[index]), \(Numbers.display(day.total.calories, decimals: 0)) ккал")
                            if day.total.calories == 0 {
                                PointMark(x: .value("День", Double(index)), y: .value("Калории", 0.0)).foregroundStyle(Palette.green).symbolSize(35)
                            }
                        }
                        if let budget = day.budget, !budget.awaitingActivity {
                            RuleMark(xStart: .value("Начало", Double(index) - 0.34), xEnd: .value("Конец", Double(index) + 0.34), y: .value("Ориентир", budget.target))
                                .foregroundStyle(Palette.blue.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .accessibilityLabel("\(weekdays[index]), ориентир \(Numbers.display(budget.target, decimals: 0)) ккал")
                        }
                    }
                }.chartXScale(domain: -0.5...6.5).chartYScale(domain: 0...ceiling)
                    .chartXAxis {
                        AxisMarks(values: (0...6).map(Double.init)) { value in
                            AxisValueLabel {
                                if let position = value.as(Double.self), (0...6).contains(Int(position)) {
                                    Text(weekdays[Int(position)]).font(.system(size: 11, weight: .medium)).foregroundStyle(report.days[Int(position)].hasEntries ? Palette.ink : Palette.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine(stroke: StrokeStyle(dash: [3, 4])); AxisValueLabel() } }
                    .frame(height: 215)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "minus").foregroundStyle(Palette.blue)
                    Text("Синий пунктир — ориентир по текущим настройкам цели. В режиме Apple Watch он показан только за дни с данными активности. Исторические настройки цели не сохранялись.")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                if report.loggedDays.isEmpty {
                    Text("За эту неделю пока нет записей о питании.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func macros(_ report: WeekSummary) -> some View {
        let average = report.average ?? Nutrients()
        let values: [(String, Double, Double, Color)] = [("Белки", average.protein, 4, Palette.green), ("Жиры", average.fat, 9, Palette.orange), ("Углеводы", average.carbs, 4, Palette.blue)]
        let energy = values.reduce(0) { $0 + $1.1 * $1.2 }
        return Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Баланс БЖУ").font(.system(size: 19, weight: .semibold))
                HStack(spacing: 26) {
                    ZStack {
                        if energy > 0 {
                            Chart {
                                ForEach(values, id: \.0) { item in
                                    SectorMark(angle: .value(item.0, item.1 * item.2), innerRadius: .ratio(0.76), angularInset: 3)
                                        .foregroundStyle(item.3).cornerRadius(4)
                                        .accessibilityLabel("\(item.0): \(Numbers.display(item.1 * item.2 / energy * 100, decimals: 0)) процентов энергии по БЖУ")
                                }
                            }
                        } else { Circle().stroke(Palette.line.opacity(0.5), lineWidth: 18).padding(12) }
                        VStack(spacing: 5) {
                            Text(report.average == nil ? "—" : "БЖУ").font(.system(size: 23, weight: .semibold, design: .rounded))
                            Text("за неделю").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.accessibilityHidden(true)
                    }.frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(values, id: \.0) { item in
                            HStack {
                                Circle().fill(item.3).frame(width: 7, height: 7)
                                Text(item.0).font(.system(size: 13))
                                Spacer()
                                Text(report.average == nil ? "—" : "\(Numbers.display(item.1)) г / день").font(.system(size: 14, weight: .medium, design: .rounded))
                                Text(energy > 0 ? "\(Numbers.display(item.1 * item.2 / energy * 100, decimals: 0))%" : "—")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(width: 40, alignment: .trailing)
                            }
                        }
                        Text("Средние — по дням с записями. Кольцо показывает долю энергии по формуле Б × 4, Ж × 9, У × 4; она может отличаться от калорий на упаковке.")
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func dayList(_ report: WeekSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 17) {
                Text("Каждый день в деталях").font(.system(size: 19, weight: .semibold))
                Text("Нажмите на день, чтобы открыть его записи. Активность включает импорт с часов и ручной ввод.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                ForEach(Array(report.days.enumerated()), id: \.offset) { index, day in
                    Button {
                        model.selectedDay = day.date; model.screen = .diary
                    } label: {
                        HStack(spacing: 14) {
                            VStack(spacing: 4) {
                                Text(weekdays[index].uppercased()).font(.system(size: 9, weight: .medium))
                                Text(day.date.formatted(.dateTime.day())).font(.system(size: 19, weight: .semibold, design: .rounded))
                            }.frame(width: 44, height: 51).background(day.hasEntries ? Palette.mint.opacity(0.7) : Palette.line.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.isFuture ? "Ещё впереди" : day.hasEntries ? "\(day.estimated ? "≈ " : "")\(Numbers.display(day.total.calories, decimals: 0)) ккал" : "Нет записей")
                                    .font(.system(size: 14, weight: .medium))
                                Text(day.hasEntries ? "Б \(Numbers.display(day.total.protein)) · Ж \(Numbers.display(day.total.fat)) · У \(Numbers.display(day.total.carbs)) г · записей: \(day.entryCount)" : "—")
                                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Label(day.activeCalories.map { "\(Numbers.display($0, decimals: 0)) ккал" } ?? "—", systemImage: "flame")
                                    .font(.system(size: 12)).foregroundStyle(Palette.blue)
                                Text(day.activeCalories == nil ? "нет данных активности" : "активные калории").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(day.isFuture)
                    if index < 6 { Rectangle().fill(Palette.line.opacity(0.5)).frame(height: 1) }
                }
            }
        }
    }

    private func moveWeek(_ offset: Int) {
        selectedDate = min(Date(), Calendar.current.date(byAdding: .day, value: offset * 7, to: selectedDate) ?? selectedDate)
    }
    private func dateRange(_ report: WeekSummary) -> String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: report.end)!
        let formatter = DateIntervalFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.dateTemplate = "d MMM yyyy"
        return formatter.string(from: report.start, to: last)
    }
}
