import Foundation

public struct MacroHint: Equatable, Sendable {
    public let title: String
    public let message: String

    public static func make(eaten: Nutrients, budget: DayBudget, hasPreferences: Bool) -> MacroHint? {
        guard let targets = budget.macroTargets else { return nil }
        let p = MacroProgress(eaten: eaten.protein, target: targets.protein)
        let f = MacroProgress(eaten: eaten.fat, target: targets.fat)
        let c = MacroProgress(eaten: eaten.carbs, target: targets.carbs)
        let ending = " Ориентиры не нужно добирать грамм в грамм."
        if eaten.calories == 0 && eaten.protein == 0 && eaten.fat == 0 && eaten.carbs == 0 {
            return MacroHint(title: "Начнём с записей", message: "Добавь еду и напитки за день — тогда здесь появится подсказка по твоему остатку БЖУ. Отсутствие записей не означает, что ты ничего не ел.")
        }
        if budget.remaining <= 0 {
            return MacroHint(title: "Продолжай в обычном ритме", message: "Калорийный ориентир уже достигнут. Не нужно пропускать следующий приём пищи или компенсировать еду тренировкой. Ориентируйся на голод и привычный режим." + ending)
        }
        let preferenceNote = hasPreferences ? " Выбирай продукты с учётом ограничений из настроек помощника; эта быстрая подсказка не проверяет состав продуктов." : ""
        if p.fraction < 0.8 && f.fraction >= 0.9 {
            return MacroHint(title: "Белок с меньшим количеством жира", message: "До ориентира белка ещё примерно \(Numbers.display(p.remaining)) г, а жиры уже близки к ориентиру или выше него. Для следующего приёма пищи выбери источник белка с небольшим количеством жира."
                             + (hasPreferences ? "" : " Например, нежирный творог или белую рыбу; соус можно подать отдельно.") + preferenceNote + ending)
        }
        let candidates = [("protein", p.fraction), ("carbs", c.fraction), ("fat", f.fraction)]
        let lowest = candidates.min { $0.1 < $1.1 }!
        if lowest.1 >= 0.8 {
            return MacroHint(title: "БЖУ близки к ориентирам", message: "Белки, жиры и углеводы уже набраны примерно на 80% или больше. Для следующего приёма пищи выбирай привычную разнообразную еду по голоду." + preferenceNote + ending)
        }
        switch lowest.0 {
        case "protein":
            return MacroHint(title: "Можно добавить источник белка", message: "До ориентира белка ещё примерно \(Numbers.display(p.remaining)) г. В следующем приёме пищи можно сделать акцент на белке."
                             + (hasPreferences ? "" : " Например, добавить к гарниру рыбу или бобовые.") + preferenceNote + ending)
        case "carbs":
            return MacroHint(title: "Есть место для гарнира", message: "До ориентира углеводов ещё примерно \(Numbers.display(c.remaining)) г. Следующий приём пищи можно дополнить гарниром."
                             + (hasPreferences ? "" : " Например, гречкой, овсянкой или цельнозерновым хлебом.") + preferenceNote + ending)
        default:
            return MacroHint(title: "Жиры тоже часть питания", message: "До ориентира жиров ещё примерно \(Numbers.display(f.remaining)) г. Можно добавить источник жиров к обычной еде."
                             + (hasPreferences ? "" : " Например, немного оливкового масла в салат или авокадо.") + preferenceNote + ending)
        }
    }
}
