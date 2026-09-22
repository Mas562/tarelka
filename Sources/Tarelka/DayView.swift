import SwiftUI
import AppKit
import NutritionCore

struct DayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @State private var date = Date()
    @State private var showProfile = false
    @State private var showWatchHelp = false
    private var total: Nutrients { model.total(on: date) }
    private var budget: DayBudget? { personal.data.budget(on: date, eaten: total.calories) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "Питание и активность")
                        Text("Мой день").font(.system(size: 32, weight: .semibold)).tracking(-0.9)
                    }
                    Spacer()
                    GlassGroup {
                        HStack(spacing: 10) {
                            ModernDatePicker(title: "Выбрать день", selection: $date, maximumDate: Date())
                            Button("Сегодня") { date = Date() }.buttonStyle(SoftButton())
                        }
                    }
                }.arrive()
                Group {
                    if let budget {
                        PremiumEnergyCard(budget: budget,
                            baseTitle: personal.data.manualTarget != nil ? "Твоя база" : budget.creditsActivity ? "Покой" : "Норма",
                            goal: personal.data.settings.goal.rawValue, isToday: Calendar.current.isDateInToday(date)) { showProfile = true }
                    } else { budgetCard }
                }.arrive(delay: 0.06)
                DailyMacrosCard(eaten: total, budget: budget) { showProfile = true }.arrive(delay: 0.12)
                if Calendar.current.isDateInToday(date) { CoachCard().arrive(delay: 0.18) }
                activityCard.arrive(delay: 0.22)
                DisclosureGroup("Передача данных с Apple Watch", isExpanded: $showWatchHelp) {
                    WatchHelpView().padding(.top, 12)
                }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 4)
            }.padding(30).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.sheet(isPresented: $showProfile) { ProfileEditor() }
    }
    private var budgetCard: some View {
        Card(padding: 28) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(personal.data.settings.goal.rawValue, systemImage: personal.data.settings.goal == .gentleLoss ? "leaf" : "heart")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.green)
                    Spacer()
                    Button(budget == nil ? "Рассчитать норму" : "Цель и норма") { showProfile = true }.buttonStyle(SoftButton())
                }
                if let budget {
                    HStack(spacing: 26) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(Calendar.current.isDateInToday(date) ? "Энергия на сегодня" : "Энергия за день").font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                            Text(budget.creditsActivity ? "Движение добавляет энергию в твой дневной бюджет." : "Обычная активность уже включена в дневную норму.")
                                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .top, spacing: 10) {
                                metric(personal.data.manualTarget != nil ? "Твоя база" : budget.creditsActivity ? "Покой" : "Норма", value: budget.base, sign: "", color: Palette.ink)
                                if budget.creditsActivity {
                                    metric("Активность", value: budget.active, sign: "+", color: Palette.blue)
                                }
                                metric("Съедено", value: budget.eaten, sign: "−", color: Palette.green)
                            }
                            if budget.deficit > 0 {
                                Text("− \(Numbers.display(budget.deficit, decimals: 0)) ккал · мягкий дефицит уже учтён")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.violet)
                            }
                            if budget.awaitingActivity {
                                Text("Ждём данные активности. Пока остаток рассчитан только от базы.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        EnergyRing(budget: budget)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Palette.green).frame(width: 5, height: 5)
                        Text("Еда и напитки").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Circle().fill(Palette.blue).frame(width: 5, height: 5).padding(.leading, 9)
                        Text("Активность").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text("Ориентир на день: \(Numbers.display(budget.target, decimals: 0)) ккал")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                    }
                    if !Calendar.current.isDateInToday(date) {
                        Text("Для выбранной даты используются текущие параметры нормы.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                } else {
                    HStack(spacing: 25) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Познакомимся чуть ближе?").font(.system(size: 27, weight: .semibold))
                            Text("Рост, вес, возраст и пол помогут рассчитать базу. Калории с часов добавятся к ней за каждый день.")
                                .font(.system(size: 14)).lineSpacing(4).foregroundStyle(Palette.secondary)
                            Button("Рассчитать мой баланс") { showProfile = true }.buttonStyle(SoftButton())
                        }
                        Image(systemName: "figure.mind.and.body").font(.system(size: 80, weight: .ultraLight)).foregroundStyle(Palette.green.opacity(0.7)).padding(20)
                    }.padding(.vertical, 14)
                }
            }
        }
    }
    private func metric(_ title: String, value: Double?, sign: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            Text(value.map { sign + Numbers.display($0, decimals: 0) } ?? "—")
                .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.7).lineLimit(1).animatedNumber(value ?? 0)
            Text("ккал").font(.system(size: 9)).foregroundStyle(Palette.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Label("Движение в твоём дне", systemImage: "applewatch").font(.system(size: 19, weight: .semibold))
                    Spacer()
                    Text("APPLE WATCH").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.blue)
                }
                if let activity = personal.activity(on: date) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(Numbers.display(activity.activeCalories, decimals: 0)).font(.system(size: 38, weight: .semibold, design: .rounded)).animatedNumber(activity.activeCalories)
                        Text("активных ккал").foregroundStyle(Palette.secondary)
                    }
                    Text("\(activity.source.rawValue) · обновлено \(activity.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Text("За этот день данных пока нет").font(.system(size: 20, weight: .medium))
                    Text("Импортируй данные с iPhone или перенеси значение красного кольца «Подвижность» вручную.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Text(personal.data.settings.accounting == .watch
                     ? "Эти калории прибавляются к базе. Вводи только активную энергию — без расхода в покое. Показания часов приблизительные."
                     : "Выбран расчёт по обычной активности. Чтобы прибавлять калории часов, выбери «Покой + Apple Watch» в настройках нормы.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                GlassGroup {
                    HStack(spacing: 14) {
                        Button("Импорт с iPhone…") { personal.chooseActivityFile(link: false) }.buttonStyle(SoftButton())
                        Button("Подключить файл…") { personal.chooseActivityFile(link: true) }.buttonStyle(SoftButton())
                        if personal.importing { ProgressView().controlSize(.small) }
                    }.disabled(personal.importing || personal.storageError != nil)
                }
                if let filename = personal.data.linkedFileName {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(filename, systemImage: "link").font(.system(size: 12, weight: .medium))
                            Text("Проверка раз в минуту, пока «Тарелка» открыта.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button("Обновить") { personal.refreshLinkedFile(force: true) }.disabled(personal.importing)
                        Button("Отключить") { personal.unlinkActivityFile() }.disabled(personal.importing)
                    }
                }
                if let status = personal.status { Text(status).font(.system(size: 11)).foregroundStyle(Palette.green) }
                ManualActivityEditor(date: date).id(DayKey.string(date))
            }
        }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var height = ""
    @State private var weight = ""
    @State private var age = ""
    @State private var sex: FormulaSex?
    @State private var activity = ActivityLevel.low
    @State private var accounting = ActivityAccounting.watch
    @State private var goal = NutritionGoal.maintain
    @State private var useManual = false
    @State private var target = ""
    @State private var loaded = false
    private var profile: CalorieProfile? {
        guard let h = Numbers.parse(height), let w = Numbers.parse(weight), let a = Int(age), let sex else { return nil }
        let value = CalorieProfile(height: h, weight: w, age: a, sex: sex, activity: activity)
        return value.isValid ? value : nil
    }
    private var manualTarget: Double? { Numbers.parse(target).flatMap { (500...10_000).contains($0) ? $0 : nil } }
    private var preview: DayBudget? {
        guard useManual ? manualTarget != nil : profile != nil else { return nil }
        var data = personal.data
        data.profile = useManual ? personal.data.profile : profile
        data.manualTarget = useManual ? manualTarget : nil
        data.budgetSettings = BudgetSettings(accounting: accounting, goal: goal)
        return data.budget(on: Date(), eaten: 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Твоя цель и дневной баланс").font(.system(size: 26, weight: .semibold)).tracking(-0.7)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Цель", selection: $goal) { ForEach(NutritionGoal.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Picker("Учёт активности", selection: $accounting) { ForEach(ActivityAccounting.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Text(accounting.detail).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Toggle("Указать свою базовую норму", isOn: $useManual).font(.system(size: 13))
                    if useManual {
                        labeledField("База, ккал в день", text: $target)
                        Text(accounting == .watch ? "Активные калории прибавятся сверху. В этой базе не должна уже учитываться та же активность. Дефицит автоматически не вычитается: твоя база считается готовой целью." : "Укажи готовый дневной ориентир. Калории часов и дополнительный дефицит сверху не учитываются.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    } else {
                        HStack(spacing: 14) {
                            labeledField("Рост, см", text: $height); labeledField("Вес, кг", text: $weight); labeledField("Возраст, лет", text: $age)
                        }
                        Picker("Пол для формулы", selection: $sex) {
                            Text("Выбери").tag(Optional<FormulaSex>.none)
                            ForEach(FormulaSex.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        if accounting == .estimated {
                            Picker("Обычная активность", selection: $activity) { ForEach(ActivityLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            Text(activity.detail).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    if let preview {
                        Card(padding: 19) {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("≈ \(Numbers.display(preview.target, decimals: 0)) ккал").font(.system(size: 32, weight: .semibold, design: .rounded)).animatedNumber(preview.target)
                                Text("База \(Numbers.display(preview.base, decimals: 0)) + активность \(Numbers.display(preview.creditedActivity, decimals: 0)) − дефицит \(Numbers.display(preview.deficit, decimals: 0))")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                Text(preview.awaitingActivity ? "Предварительно: данных активности за сегодня ещё нет." : "Ориентир с уже полученной активностью за сегодня.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                if let targets = preview.macroTargets {
                                    Divider().padding(.vertical, 5)
                                    MacroTargetSummary(targets: targets)
                                }
                            }
                        }
                    } else {
                        Text(useManual ? "Укажи базу от 500 до 10 000 ккал." : "Заполни параметры: рост 100–250 см, вес 25–350 кг, возраст 18–120 лет.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    MacroMethodDetails()
                    if goal == .gentleLoss {
                        Text("Мягкий дефицит: 10% от расчётного расхода, максимум 300 ккал. Программа не снижает ориентир ниже 1500 ккал для мужчин и 1200 для женщин; при низком ИМТ дефицит отключён. Эти границы не гарантируют подходящую лично тебе норму. Для ручной базы дефицит уже должен быть учтён в её значении.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Text("Расход в покое оценивается по Миффлину — Сан Жеору. Это ориентир, а не точное измерение потребности. Расчёт для взрослых; не предназначен для беременности, грудного вскармливания или лечебной диеты. Изменение веса за месяц не гарантируется.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Link("О формуле", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!).font(.system(size: 11))
                }.padding(.vertical, 4).padding(.horizontal, 2)
            }
            if let error = personal.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.orange) }
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button("Сохранить норму") {
                    if personal.saveProfile(useManual ? personal.data.profile : profile, target: useManual ? manualTarget : nil,
                                            settings: BudgetSettings(accounting: accounting, goal: goal)) { dismiss() }
                }.buttonStyle(PrimaryButton()).disabled((useManual ? manualTarget == nil : profile == nil) || personal.storageError != nil)
            }
        }.padding(28).frame(width: 620, height: 720).background(Palette.background)
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let profile = personal.data.profile {
                    height = Numbers.input(profile.height); weight = Numbers.input(profile.weight); age = String(profile.age)
                    sex = profile.sex; activity = profile.activity
                }
                if let value = personal.data.manualTarget { target = Numbers.input(value); useManual = true }
                accounting = personal.data.settings.accounting; goal = personal.data.settings.goal
            }
    }
}

struct WatchHelpView: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Как передать данные с Apple Watch", systemImage: "iphone.and.arrow.forward").font(.system(size: 17, weight: .semibold))
                Text("Данные приходят через приложение «Здоровье» на связанном iPhone. На часы ничего устанавливать не нужно. Прямого доступа к «Здоровью» с Mac нет.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                DisclosureGroup("Бесплатный импорт через AirDrop") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Откройте «Фитнес» на iPhone и дождитесь обновления колец с часов.")
                        Text("2. В «Здоровье» нажмите свой профиль → «Экспортировать все данные о здоровье». Передайте ZIP на Mac через AirDrop.")
                        Text("3. Откройте ZIP в Finder. В «Тарелке» нажмите «Импорт с iPhone…» и выберите apple_health_export/export.xml.")
                        Text("Импортируются только дневные итоги активных калорий. Повторный импорт обновляет дни. Для свежих показаний повторите экспорт; это не постоянная синхронизация.")
                        Link("Инструкция Apple по экспорту", destination: URL(string: "https://support.apple.com/en-gb/guide/iphone/iph5ede58c3d/ios")!)
                    }.font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 12)
                }
                DisclosureGroup("Автообновление из файла на Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("«Подключить файл…» связывает приложение с одним XML или JSON. Когда файл обновляется, «Тарелка» перечитывает его раз в минуту. Сам экспорт с iPhone эта кнопка не запускает.")
                        Text("Для регулярной передачи можно настроить «Команды» на iPhone: получить сегодняшнюю активную энергию только от ваших Apple Watch, сложить значения в ккал и сохранить дневной итог в JSON на iCloud Drive. Нужны разрешение на чтение «Здоровья» и свободное место в iCloud.")
                        Text("Настройка команды выполняется на iPhone. Перед автоматизацией проверьте её итог по «Фитнесу» — данные от нескольких источников нельзя просто складывать. Формат файла и последовательность действий — в подробной инструкции ниже.")
                    }.font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 12)
                }
                if let guide = Bundle.main.url(forResource: "AppleWatch", withExtension: "md") {
                    Button("Открыть подробную инструкцию") { NSWorkspace.shared.open(guide) }.buttonStyle(SoftButton())
                }
            }
        }
    }
}

/// Editing is local: neither the day dashboard nor the model is refreshed for every digit.
struct ManualActivityEditor: View {
    @EnvironmentObject var personal: PersonalStore
    @EnvironmentObject var coach: CoachStore
    let date: Date
    @State private var calories = ""
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Ввести активные калории вручную", isExpanded: $expanded) {
            HStack(spacing: 12) {
                TextField("Активные ккал", text: $calories).inputSurface()
                    .accessibilityLabel("Активные калории вручную")
                    .onSubmit(save)
                Button("Сохранить", action: save)
                    .buttonStyle(.bordered)
                    .disabled(parsed == nil || personal.storageError != nil)
            }.padding(.top, 4)
        }.font(.system(size: 12))
            .onChange(of: expanded) { _, open in
                if open { calories = personal.activity(on: date).map { Numbers.input($0.activeCalories) } ?? "" }
            }
    }
    private var parsed: Double? {
        Numbers.parse(calories).flatMap { (0...30_000).contains($0) ? $0 : nil }
    }
    private func save() {
        guard let value = parsed, personal.saveManualActivity(calories: value, date: date) else { return }
        expanded = false
    }
}
