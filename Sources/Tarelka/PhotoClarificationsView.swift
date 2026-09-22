import SwiftUI
import NutritionCore

struct PhotoClarificationsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Уточним то, чего не видно на фото", systemImage: "bubble.left.and.text.bubble.right")
                .font(.system(size: 17, weight: .semibold))
            Text("Ответь только на то, что знаешь. Количества указывай для своей порции и уточни, входят ли добавки в её взвешенный вес. Если не знаешь — оставь поле пустым.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            ForEach(model.clarificationQuestions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.question).font(.system(size: 12, weight: .medium))
                    TextField(question.example, text: Binding(
                        get: { model.clarificationAnswers[question.id] ?? "" },
                        set: { model.clarificationAnswers[question.id] = String($0.prefix(300)) }
                    ), axis: .vertical).textFieldStyle(.plain).lineLimit(1...3)
                        .font(.system(size: 12)).padding(11).background(Palette.surface.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel(question.question)
                }
            }
            Text("Пересчёт заново распознает фото и заменит текущий состав, включая ручные правки. Если добавки не входят в вес, сначала поправь общий вес порции выше.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            HStack {
                Button("Пересчитать с ответами") { model.analyze(refining: true) }
                    .buttonStyle(SoftButton()).disabled(!model.hasClarificationAnswers || model.photoData == nil || model.parsedWeight == nil)
                Button(model.hasClarificationAnswers ? "Оставить исходную оценку" : "Оставить без уточнений") { model.skipClarifications() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Text(model.provider == .local ? "Повторный расчёт бесплатный и работает на этом Mac." : "Повторный запрос к платному OpenAI API: фото и ответы отправятся в OpenAI.")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(18).background(Palette.mint.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
