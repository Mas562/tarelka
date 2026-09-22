import SwiftUI

struct ModernDatePicker: View {
    let title: String
    @Binding var selection: Date
    var maximumDate: Date? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: "calendar").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.green)
                Text(selection.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 13).frame(height: 38).foregroundStyle(Palette.ink)
                .liquidSurface(radius: 14, tint: Palette.mint.opacity(0.15), interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            CalendarPanel(selection: $selection, maximumDate: maximumDate) { presented = false }
                .preferredColorScheme(colorScheme)
        }
    }
}

private struct CalendarPanel: View {
    @Binding var selection: Date
    let maximumDate: Date?
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month: Date
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 4), count: 7)

    init(selection: Binding<Date>, maximumDate: Date?, dismiss: @escaping () -> Void) {
        _selection = selection
        self.maximumDate = maximumDate
        self.dismiss = dismiss
        _month = State(initialValue: CalendarDates.monthStart(selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ВЫБЕРИ ДЕНЬ").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.secondary)
                    Text("\(month.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU"))).capitalized) \(String(calendar.component(.year, from: month)))")
                        .font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 10)
                navigation(-1, symbol: "chevron.left", label: "Предыдущий месяц")
                navigation(1, symbol: "chevron.right", label: "Следующий месяц")
            }
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"].enumerated()), id: \.offset) { _, day in
                        Text(day).font(.system(size: 9, weight: .semibold)).tracking(0.7)
                            .foregroundStyle(Palette.secondary).frame(width: 38, height: 20)
                    }
                }.accessibilityHidden(true)
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(CalendarDates.days(in: month), id: \.self) { day in dayButton(day) }
                }
            }
            Rectangle().fill(Palette.line.opacity(0.45)).frame(height: 1)
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                    Text("Сегодня, \(Date().formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))))")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("К сегодня") { select(Date()) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                    .disabled(!CalendarDates.isAllowed(Date(), through: maximumDate))
            }
        }
        .padding(22).frame(width: 334).foregroundStyle(Palette.ink)
        .background {
            ZStack(alignment: .topLeading) {
                Palette.background
                RadialGradient(colors: [Palette.mint.opacity(0.65), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
                Palette.surface.opacity(0.4)
            }
        }
    }

    private func navigation(_ offset: Int, symbol: String, label: String) -> some View {
        let target = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { month = target }
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 29, height: 31)
                .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(label)
            .disabled(!CalendarDates.isAllowed(target, through: maximumDate))
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let allowed = CalendarDates.isAllowed(day, through: maximumDate)
        return Button { select(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: selected || today ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : allowed ? (inMonth ? Palette.ink : Palette.secondary.opacity(0.65)) : Palette.secondary.opacity(0.3))
                .frame(width: 38, height: 38)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Palette.blue, Palette.green], startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else if today {
                        RoundedRectangle(cornerRadius: 13).fill(Palette.mint.opacity(0.65))
                    }
                }
                .overlay(alignment: .bottom) {
                    if today { Circle().fill(selected ? .white : Palette.green).frame(width: 3, height: 3).padding(.bottom, 4) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(CalendarDayStyle())
        .disabled(!allowed)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
        .accessibilityValue(today ? "Сегодня" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ day: Date) {
        guard CalendarDates.isAllowed(day, through: maximumDate) else { return }
        selection = CalendarDates.replacingDay(of: selection, with: day)
        dismiss()
    }
}

private struct CalendarDayStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CalendarDayFeedback(configuration: configuration)
    }
    private struct CalendarDayFeedback: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Palette.green.opacity(hovered ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 13))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct ModernDateTimePicker: View {
    @Binding var selection: Date
    var body: some View {
        HStack(spacing: 10) {
            ModernDatePicker(title: "Дата", selection: $selection)
            DatePicker("Время", selection: $selection, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.field).fixedSize()
        }
    }
}
