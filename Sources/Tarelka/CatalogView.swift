import SwiftUI
import NutritionCore

struct CatalogSettingsView: View {
    @AppStorage("useFoodCatalog") private var useCatalog = true
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("КБЖУ из справочника", systemImage: "books.vertical").font(.system(size: 18, weight: .semibold))
                Toggle("После фото брать КБЖУ из базы продуктов", isOn: $useCatalog)
                Text("\(FoodCatalog.shared.foods.count) продуктов USDA, бесплатно и без интернета. Фото определяет состав и доли, а ты подтверждаешь подходящий продукт и способ приготовления. При отсутствии совпадения поля КБЖУ останутся пустыми: можно выбрать свои данные с упаковки или ввести их вручную.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text("Значения справочника — средние на 100 г съедобной части. Сырой вес, готовый вес, масло и панировка дают разные результаты. Для конкретной марки точнее данные с её упаковки.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Link("Источник: USDA FoodData Central · SR Legacy 2018", destination: URL(string: "https://fdc.nal.usda.gov/download-datasets/")!).font(.system(size: 11))
            }
        }
    }
}

struct CatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [CatalogFood] = []
    @State private var selected: CatalogFood?
    @State private var grams: String
    @State private var searching = false
    let actionTitle: String
    let requiresWeight: Bool
    let onChoose: (CatalogFood, Double) -> Void
    init(query: String = "", grams: String = "100", actionTitle: String = "Использовать эти КБЖУ", requiresWeight: Bool = true, onChoose: @escaping (CatalogFood, Double) -> Void) {
        self.actionTitle = actionTitle; self.requiresWeight = requiresWeight
        _query = State(initialValue: query); _grams = State(initialValue: grams); self.onChoose = onChoose
    }
    private var weight: Double? { Numbers.parse(grams).flatMap { Numbers.validWeight($0) ? $0 : nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Справочник продуктов").font(.system(size: 24, weight: .semibold))
                    Text("\(FoodCatalog.shared.foods.count) записей · КБЖУ на 100 г · работает без интернета").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Закрыть") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
            }
            TextField("Например: курица жареная, рис, гречка", text: $query).inputSurface().accessibilityLabel("Поиск в справочнике")
            Text("Ищи короткими словами на русском или английском. Проверь состояние продукта: сырой или готовый, с кожей, маслом или панировкой. База использует граммы, не миллилитры.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    if !searching && results.isEmpty { Text("Совпадений нет. Упрости запрос или используй данные с упаковки.").padding(25).foregroundStyle(Palette.secondary) }
                    ForEach(results) { food in
                        Button { selected = food } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selected?.id == food.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.green)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(food.displayName).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                    Text(food.name).font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                                    Text("\(Numbers.display(food.per100.calories)) ккал · Б \(Numbers.display(food.per100.protein)) · Ж \(Numbers.display(food.per100.fat)) · У \(Numbers.display(food.per100.carbs))").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == food.id ? Palette.mint : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(minHeight: 180, maxHeight: .infinity)
            if let selected {
                Link("USDA · запись \(selected.id) ↗", destination: selected.sourceURL).font(.system(size: 11))
                if requiresWeight {
                    labeledField("Вес съедобной части, г", text: $grams)
                    if let weight { Text("В порции: \(Numbers.display(selected.per100.scaled(by: weight / 100).calories)) ккал").foregroundStyle(Palette.green) }
                }
            }
            Button(actionTitle) { if let selected, let weight { onChoose(selected, weight); dismiss() } }
                .buttonStyle(PrimaryButton()).disabled(selected == nil || weight == nil || searching)
        }.padding(24).frame(width: 680, height: 690).background(Palette.background).foregroundStyle(Palette.ink)
            .task(id: query) {
                selected = nil; searching = true
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                let search = query
                let found = await Task.detached(priority: .userInitiated) { FoodCatalog.shared.search(search) }.value
                guard !Task.isCancelled else { return }
                results = found; searching = false
            }
    }
}
