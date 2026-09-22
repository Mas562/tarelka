import SwiftUI
import NutritionCore

struct ProductsView: View {
    @EnvironmentObject var personal: PersonalStore
    @State private var search = ""
    private struct EditorRequest: Identifiable {
        let id = UUID()
        let product: SavedProduct?
        var scanOnOpen = false
    }
    @State private var editor: EditorRequest?
    @State private var deleting: SavedProduct?
    @State private var showCatalog = false
    private var products: [SavedProduct] {
        personal.data.products.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Данные с вашей упаковки")
                HStack {
                    Text("Мои продукты").font(.system(size: 31, weight: .semibold))
                    Spacer()
                    Button { editor = EditorRequest(product: nil, scanOnOpen: true) } label: { Label("С фото упаковки", systemImage: "text.viewfinder") }.buttonStyle(PrimaryButton())
                    Button { editor = EditorRequest(product: nil) } label: { Image(systemName: "plus") }.buttonStyle(SoftButton()).accessibilityLabel("Новый продукт вручную")
                }
                Text("Сохраните калории и БЖУ на 100 г или 100 мл один раз. Затем указывайте только вес или объём.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Button { showCatalog = true } label: { Label("Открыть справочник · 7 793 продукта", systemImage: "books.vertical") }.buttonStyle(SoftButton())
                TextField("Найти продукт", text: $search).inputSurface().accessibilityLabel("Найти продукт")
                if products.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(search.isEmpty ? "Ваша библиотека пока пуста" : "Ничего не найдено", systemImage: "shippingbox")
                                .font(.system(size: 18, weight: .medium))
                            Text("Например, добавьте сосиски и сыр с данными их упаковок. Продукты доступны без интернета.")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }.padding(.vertical, 20)
                    }
                }
                ForEach(products) { product in
                    Card(padding: 18) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(product.name).font(.system(size: 17, weight: .medium))
                                Text("\(Numbers.display(product.per100.calories)) ккал · Б \(Numbers.display(product.per100.protein)) · Ж \(Numbers.display(product.per100.fat)) · У \(Numbers.display(product.per100.carbs)) г на \(product.unit.basis)")
                                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                if product.caloriesFromMacros { Text("Калории приблизительно рассчитаны по БЖУ").font(.system(size: 10)).foregroundStyle(Palette.orange) }
                            }
                            Spacer()
                            Button("Изменить") { editor = EditorRequest(product: product) }.buttonStyle(SoftButton())
                            Button { deleting = product } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                                .accessibilityLabel("Удалить продукт \(product.name)")
                        }
                    }
                }
                Text("Изменение продукта в библиотеке не меняет уже записанные блюда.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.padding(32).frame(maxWidth: 1060).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showCatalog) {
            CatalogPicker(actionTitle: "Сохранить в мои продукты", requiresWeight: false) { food, _ in
                _ = personal.saveProduct(SavedProduct(name: food.displayName, per100: food.per100, source: food.source))
            }
        }
        .sheet(item: $editor) { request in ProductEditor(product: request.product, scanOnOpen: request.scanOnOpen) }
        .confirmationDialog("Удалить продукт из библиотеки?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Удалить продукт", role: .destructive) { if let deleting { personal.deleteProduct(deleting) }; deleting = nil }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: { Text("Записанные блюда сохранят прежние калории и БЖУ.") }
    }
}

struct ProductEditor: View {
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.dismiss) private var dismiss
    private let productID: UUID
    private let source: NutritionSource?
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @State private var derive: Bool
    @State private var unit: PortionUnit
    @State private var showScanner: Bool
    init(product: SavedProduct?, defaultUnit: PortionUnit = .grams, scanOnOpen: Bool = false) {
        _showScanner = State(initialValue: scanOnOpen)
        _unit = State(initialValue: product?.unit ?? defaultUnit)
        productID = product?.id ?? UUID()
        source = product?.source
        _name = State(initialValue: product?.name ?? "")
        _calories = State(initialValue: product.map { Numbers.input($0.per100.calories) } ?? "")
        _protein = State(initialValue: product.map { Numbers.input($0.per100.protein) } ?? "")
        _fat = State(initialValue: product.map { Numbers.input($0.per100.fat) } ?? "")
        _carbs = State(initialValue: product.map { Numbers.input($0.per100.carbs) } ?? "")
        _derive = State(initialValue: product?.caloriesFromMacros ?? false)
    }
    private var value: SavedProduct? {
        guard let p = Numbers.parse(protein), let f = Numbers.parse(fat), let c = Numbers.parse(carbs),
              let kcal = derive ? Optional(4 * p + 9 * f + 4 * c) : Numbers.parse(calories) else { return nil }
        var value = SavedProduct(id: productID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 per100: Nutrients(calories: kcal, protein: p, fat: f, carbs: c), caloriesFromMacros: derive, unit: unit)
        if source?.per100 == value.per100 { value.source = source }
        return value.isValid ? value : nil
    }
    var body: some View {
        if showScanner {
            LabelScannerView(unit: unit, onCancel: { showScanner = false }) { nutrients, scannedUnit in
                unit = scannedUnit; derive = false
                calories = Numbers.input(nutrients.calories); protein = Numbers.input(nutrients.protein)
                fat = Numbers.input(nutrients.fat); carbs = Numbers.input(nutrients.carbs)
                showScanner = false
            }
        } else { editorForm }
    }
    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(unit == .grams ? "Продукт с упаковки" : "Напиток с упаковки").font(.system(size: 25, weight: .semibold))
            Button { showScanner = true } label: { Label("Заполнить с фото упаковки", systemImage: "text.viewfinder") }.buttonStyle(SoftButton())
            Text("Перенесите значения на \(unit.basis). Если на упаковке указана порция, сначала пересчитайте её на \(unit.basis).")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Picker("Значения с упаковки", selection: $unit) {
                Text("На 100 г").tag(PortionUnit.grams)
                Text("На 100 мл").tag(PortionUnit.milliliters)
            }.pickerStyle(.segmented)
            labeledField("Название продукта", text: $name)
            HStack(spacing: 14) {
                labeledField("Белки, г", text: $protein)
                labeledField("Жиры, г", text: $fat)
                labeledField("Углеводы, г", text: $carbs)
            }
            Toggle("На упаковке только БЖУ — оценить калории", isOn: $derive).font(.system(size: 12))
            if derive {
                Text("≈ \(value.map { Numbers.display($0.per100.calories) } ?? "—") ккал на \(unit.basis) · 4 × Б + 9 × Ж + 4 × У")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.green)
                Text("Это оценка: клетчатка, сахарозаменители и округление могут давать отличие от упаковки.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            } else { labeledField("Калории, ккал на \(unit.basis)", text: $calories) }
            Text("Для отсутствующего нутриента введите 0. Укажите БЖУ в граммах на \(unit.basis).")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if let error = personal.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.orange) }
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button("Сохранить продукт") { if let value, personal.saveProduct(value) { dismiss() } }
                    .buttonStyle(PrimaryButton()).disabled(value == nil || personal.storageError != nil)
            }
        }.padding(28).frame(width: 540).background(Palette.background)
    }
}

struct ProductPicker: View {
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var grams: String
    @State private var selectedID: UUID?
    @State private var showNew = false
    let unit: PortionUnit
    let onChoose: (SavedProduct, Double) -> Void
    init(initialGrams: String = "", unit: PortionUnit = .grams, onChoose: @escaping (SavedProduct, Double) -> Void) {
        _grams = State(initialValue: initialGrams); self.onChoose = onChoose; self.unit = unit
    }
    private var products: [SavedProduct] { personal.data.products.filter { $0.unit == unit } }
    private var selected: SavedProduct? { products.first { $0.id == selectedID } }
    private var weight: Double? { Numbers.parse(grams).flatMap { Numbers.validWeight($0) ? $0 : nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(unit == .grams ? "Выбрать продукт" : "Выбрать напиток").font(.system(size: 24, weight: .semibold)); Spacer()
                Button("Создать") { showNew = true }.buttonStyle(SoftButton())
            }
            TextField(unit == .grams ? "Поиск в моих продуктах" : "Поиск в моих напитках", text: $search).inputSurface()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if products.isEmpty { Text(unit == .grams ? "Добавьте первый продукт кнопкой «Создать»." : "Здесь появятся напитки с данными на 100 мл. Добавьте первый кнопкой «Создать».").padding(30).foregroundStyle(Palette.secondary) }
                    ForEach(products.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { product in
                        Button { selectedID = product.id } label: {
                            HStack {
                                Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle")
                                Text(product.name); Spacer()
                                Text("\(Numbers.display(product.per100.calories)) ккал / \(product.unit.basis)").font(.system(size: 11))
                            }.padding(13).background(selectedID == product.id ? Palette.mint : Palette.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 210)
            labeledField(unit == .grams ? "Вес этого ингредиента, г" : "Объём напитка, мл", text: $grams)
            if let selected, let weight { Text("В порции: \(Numbers.display(selected.portion(amount: weight).total.calories)) ккал").foregroundStyle(Palette.green) }
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button(unit == .grams ? "Добавить в блюдо" : "Выбрать напиток") { if let selected, let weight { onChoose(selected, weight); dismiss() } }
                    .buttonStyle(PrimaryButton()).disabled(selected == nil || weight == nil)
            }
        }.padding(28).frame(width: 580).background(Palette.background)
            .sheet(isPresented: $showNew) { ProductEditor(product: nil, defaultUnit: unit) }
    }
}

func labeledField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        FieldLabel(title: title)
        TextField(title, text: text).inputSurface().accessibilityLabel(title)
    }
}
