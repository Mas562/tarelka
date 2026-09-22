import Foundation

public struct MealClarification: Identifiable, Equatable, Sendable {
    public let id: String
    public let question: String
    public let example: String
    public init(id: String, question: String, example: String) {
        self.id = id; self.question = question; self.example = example
    }
}

public enum MealClarifications {
    /// Questions are prompts to verify unknown facts, never claims inferred from a photo.
    public static func questions(dish: String, ingredients: [String], assumptions: [String]) -> [MealClarification] {
        let text = ([dish] + ingredients + assumptions).joined(separator: " ").lowercased()
        var result = [MealClarification(id: "composition", question: "Блюдо и состав определены верно?",
                                        example: "Например: это индейка, а не курица; рис варёный")]
        if ["жар", "масл", "омлет", "котлет", "карто", "мяс", "куриц", "рыб", "овощ", "рис", "греч", "макарон"].contains(where: text.contains) {
            result.append(MealClarification(id: "cooking", question: "Как приготовлено? Сколько масла было в твоей порции?",
                                            example: "Например: запечено без масла; или 5 г масла в этой порции"))
        }
        if ["начин", "бул", "пирог", "ваф", "блин", "торт", "выпеч", "сэндвич", "бутерброд"].contains(where: text.contains) {
            result.append(MealClarification(id: "filling", question: "Какая начинка или добавки?",
                                            example: "Например: без начинки; сыр 20 г; крем, количество неизвестно"))
        } else if ["соус", "салат", "заправ", "майон", "сметан", "пельмен", "паст", "сахар"].contains(where: text.contains) {
            result.append(MealClarification(id: "extras", question: "Были соус, заправка или другие добавки?",
                                            example: "Например: сметана 15% — 20 г; или без добавок"))
        }
        return Array(result.prefix(3))
    }

    public static func answerNotes(questions: [MealClarification], answers: [String: String]) -> String {
        questions.compactMap { question in
            let answer = String((answers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            return answer.isEmpty ? nil : "\(question.question) \(answer)"
        }.joined(separator: "\n")
    }

    public static func context(notes: String, questions: [MealClarification], answers: [String: String]) -> String {
        let details = answerNotes(questions: questions, answers: answers)
        guard !details.isEmpty else { return notes }
        return notes + "\nУточнения после фото (при противоречии использовать эти более свежие сведения):\n" + details
    }
}
