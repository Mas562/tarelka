import SwiftUI
import NutritionCore

struct CoachView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @EnvironmentObject var coach: CoachStore
    @State private var question = ""
    @State private var showPreferences = false
    private var snapshot: CoachContext { CoachContext(date: Date(), meals: model.meals, personal: personal.data) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "На твоей стороне")
                        Text("Помощник по питанию").font(.system(size: 35, weight: .semibold)).tracking(-1.2)
                        Text("Небольшие изменения. Еда, которая нравится. Твой ритм.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { showPreferences = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(SoftButton()).help("Предпочтения помощника")
                }.arrive()
                CoachCard(expanded: true).arrive(delay: 0.08)
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("Подумаем о следующем приёме пищи", systemImage: "bubble.left.and.text.bubble.right").font(.system(size: 18, weight: .semibold))
                        TextField("Например: хочу ещё булку. Чем можно заменить?", text: $question, axis: .vertical)
                            .lineLimit(2...4).inputSurface().accessibilityLabel("Вопрос помощнику")
                            .onChange(of: question) { _, value in if value.count > 700 { question = String(value.prefix(700)) } }
                        HStack {
                            Text("Ответ учитывает сегодняшние записи и твои предпочтения.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            Spacer()
                            Button("Спросить помощника") { coach.schedule(snapshot, question: question, force: true) }
                                .buttonStyle(SoftButton()).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.loading || model.isAnalyzing)
                        }
                    }
                }.arrive(delay: 0.15)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(Palette.green)
                    Text("Бесплатная модель работает на этом Mac. Это общие советы по записанной еде, а не медицинские назначения. Помощник не видит незаписанные блюда и может ошибаться.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 5)
                Link("О разнообразном питании и устойчивых привычках · NIDDK", destination: URL(string: "https://www.niddk.nih.gov/health-information/weight-management/adult-overweight-obesity/eating-physical-activity")!)
                    .font(.system(size: 11))
            }.padding(30).frame(maxWidth: 1050).frame(maxWidth: .infinity)
        }.sheet(isPresented: $showPreferences) { CoachPreferences() }
    }
}

struct CoachCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @EnvironmentObject var coach: CoachStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var expanded = false
    private var snapshot: CoachContext { CoachContext(date: Date(), meals: model.meals, personal: personal.data) }
    private var currentAdvice: NutritionAdvice? { coach.context?.day == snapshot.day ? coach.advice : nil }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 13) {
                    Image(systemName: "sparkles").font(.system(size: 23, weight: .medium))
                        .symbolEffect(.pulse, isActive: coach.loading && !reduceMotion)
                        .foregroundStyle(LinearGradient(colors: [Palette.violet, Palette.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50).liquidSurface(radius: 18, tint: Palette.violet.opacity(0.07))
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Помощник по питанию · сегодня")
                        Text(coach.loading ? "Смотрю, как складывается день…" : currentAdvice?.headline ?? "Давай найдём твой баланс")
                            .font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if expanded {
                        Button { coach.schedule(snapshot, force: true) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(SoftButton()).disabled(coach.loading || model.isAnalyzing).help("Обновить совет")
                    } else {
                        Button("Открыть") { model.screen = .coach }.buttonStyle(SoftButton())
                    }
                }
                if let error = coach.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.orange)
                    Button("Настройки локальной модели") { model.screen = .settings }.buttonStyle(SoftButton())
                }
                if currentAdvice != nil && coach.context != snapshot {
                    Text("Дневник или активность изменились. Ниже сохранён прежний совет; для актуального нажми ↻. Остаток калорий и БЖУ уже пересчитан.")
                        .font(.system(size: 12)).foregroundStyle(Palette.orange)
                }
                if coach.loading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Готовлю ответ в щадящем режиме. Это может занять несколько минут.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer(minLength: 0)
                        Button("Отмена") { coach.cancel() }.buttonStyle(.plain).font(.system(size: 11))
                    }
                } else if let advice = currentAdvice {
                    Text(advice.observation).font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    if expanded {
                        if !coach.answeredQuestion.isEmpty {
                            Label(coach.answeredQuestion, systemImage: "quote.bubble").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                        adviceRow("Следующий приём пищи", text: advice.next_meal, symbol: "fork.knife", color: Palette.green)
                        adviceRow(coach.answeredQuestion.isEmpty ? "Идея на замену" : "На твой вопрос", text: advice.swap, symbol: "arrow.triangle.swap", color: Palette.blue)
                        Text(advice.encouragement).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.violet)
                        if let updated = coach.updatedAt {
                            Text("Совет ИИ · \(updated.formatted(date: .omitted, time: .shortened)) · обновляется по твоей кнопке")
                                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                    }
                } else {
                    Text("Задай вопрос или нажми ↻, чтобы получить совет по сегодняшнему дневнику. Помощник запускается только по твоей кнопке и не переделывает ответ при вводе активности.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: coach.loading)
    }
    private func adviceRow(_ title: String, text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color).frame(width: 26).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text(text).font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}
struct CoachPreferences: View {
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Помощник, который учитывает тебя").font(.system(size: 24, weight: .semibold))
            Text("Советы обновляются по кнопке. Калории и БЖУ пересчитываются сразу, без запуска нейросети.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            FieldLabel(title: "Аллергии, ограничения и предпочтения · необязательно")
            TextField("Например: аллергия на орехи; не люблю рыбу", text: $notes, axis: .vertical).lineLimit(3...6).inputSurface()
                .onChange(of: notes) { _, value in if value.count > 1000 { notes = String(value.prefix(1000)) } }
            Text("Помощник учтёт эти сведения, но состав продуктов при аллергии всё равно нужно проверять.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button("Сохранить") { if personal.saveCoachPreferences(enabled: false, notes: notes) { dismiss() } }.buttonStyle(PrimaryButton())
            }
        }.padding(28).frame(width: 580).background(Palette.background)
            .onAppear { notes = personal.data.dietaryNotes ?? "" }
    }
}
