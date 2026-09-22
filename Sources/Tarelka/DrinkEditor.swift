import SwiftUI
import UniformTypeIdentifiers
import NutritionCore

struct DrinkDraft: Identifiable {
    let id: UUID
    let original: Meal?
    var name: String
    var volume: String
    var calories: String
    var protein: String
    var fat: String
    var carbs: String
    var kind: MealKind
    var date: Date
    var isEstimate: Bool
    var assumptions: [String]

    init(meal: Meal? = nil, date: Date = Date()) {
        id = meal?.id ?? UUID(); original = meal
        name = meal?.name ?? ""; volume = meal.map { Numbers.input($0.weight) } ?? "250"
        let per100 = meal.map { $0.total.scaled(by: 100 / $0.weight) }
        calories = per100.map { Numbers.input($0.calories) } ?? ""
        protein = per100.map { Numbers.input($0.protein) } ?? ""
        fat = per100.map { Numbers.input($0.fat) } ?? ""
        carbs = per100.map { Numbers.input($0.carbs) } ?? ""
        kind = meal?.kind ?? .suggested(at: date); self.date = meal?.date ?? date
        isEstimate = meal?.isEstimate ?? false
        assumptions = meal?.assumptions ?? []
    }
    var nutrients: Nutrients? {
        guard let k = Numbers.parse(calories), let p = Numbers.parse(protein),
              let f = Numbers.parse(fat), let c = Numbers.parse(carbs) else { return nil }
        let result = Nutrients(calories: k, protein: p, fat: f, carbs: c)
        return result.isValidPer100 ? result : nil
    }
    var product: SavedProduct? {
        guard let nutrients else { return nil }
        let result = SavedProduct(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  per100: nutrients, caloriesFromMacros: isEstimate, unit: .milliliters)
        return result.isValid ? result : nil
    }
    var meal: Meal? {
        guard let product, let amount = Numbers.parse(volume), Numbers.validWeight(amount) else { return nil }
        return Meal(id: id, date: date, kind: kind, name: product.name, weight: amount,
                    ingredients: [product.portion(amount: amount)], notes: original?.notes ?? "",
                    assumptions: assumptions, isEstimate: isEstimate,
                    photoFilename: original?.photoFilename)
    }
    mutating func choose(_ product: SavedProduct, volume: Double) {
        guard product.unit == .milliliters else { return }
        name = product.name; self.volume = Numbers.input(volume)
        calories = Numbers.input(product.per100.calories); protein = Numbers.input(product.per100.protein)
        fat = Numbers.input(product.per100.fat); carbs = Numbers.input(product.per100.carbs)
        isEstimate = product.caloriesFromMacros
        assumptions = []
    }
}

struct DrinkEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: DrinkDraft
    @State private var showProducts = false
    @State private var savingProduct: SavedProduct?
    @State private var error: String?
    @StateObject private var photo = DrinkPhotoStore()
    @State private var photoPanel: NSOpenPanel?
    @State private var showLabelScanner = false
    @State private var additions = ""
    @State private var analyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisToken = UUID()
    @State private var loadedExistingPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 27))
                    .foregroundStyle(Palette.green).frame(width: 56, height: 56)
                    .liquidSurface(radius: 20, tint: Palette.mint.opacity(0.3))
                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.original == nil ? "Добавить напиток" : "Изменить напиток")
                        .font(.system(size: 26, weight: .semibold)).tracking(-0.7)
                    Text("Объём в мл · калории и БЖУ в общем дневнике")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 10) {
                        Button { showProducts = true } label: { Label("Мои напитки", systemImage: "shippingbox") }.buttonStyle(SoftButton())
                        if draft.original == nil {
                            Button("Вода без добавок") {
                                draft.choose(SavedProduct(name: "Вода", per100: Nutrients(), unit: .milliliters),
                                             volume: Numbers.parse(draft.volume).flatMap { Numbers.validWeight($0) ? $0 : nil } ?? 250)
                            }.buttonStyle(SoftButton())
                        }
                    }
                    photoSection
                    HStack(alignment: .top, spacing: 14) {
                        labeledField("Название напитка", text: $draft.name)
                        labeledField("Объём, мл", text: $draft.volume).frame(width: 125)
                    }
                    HStack(spacing: 8) {
                        Text("Порция:").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        ForEach([150, 200, 250, 330, 500], id: \.self) { amount in
                            Button("\(amount) мл") { draft.volume = String(amount) }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(Palette.mint.opacity(Numbers.parse(draft.volume) == Double(amount) ? 0.9 : 0.3), in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Пищевая ценность на 100 мл").font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 12) {
                            labeledField("Калории, ккал", text: $draft.calories)
                            labeledField("Белки, г", text: $draft.protein)
                            labeledField("Жиры, г", text: $draft.fat)
                            labeledField("Углеводы, г", text: $draft.carbs)
                        }
                        Text("Возьмите значения на 100 мл с упаковки. Если нутриента нет, введите 0. Молоко, сахар и сиропы тоже нужно учесть в составе напитка.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Запомнить в моих напитках…") { savingProduct = draft.product }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.green).disabled(draft.product == nil)
                    }.padding(17).background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                    if let meal = draft.meal {
                        MacroStrip(nutrients: meal.total, estimated: meal.isEstimate,
                                   calorieCaption: "ккал в \(Numbers.display(meal.weight)) мл")
                    } else {
                        Text("Укажите название, объём от 0,1 до 20 000 мл и все значения пищевой ценности.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel(title: "Приём пищи")
                            Picker("Приём пищи", selection: $draft.kind) {
                                ForEach(MealKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 125)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel(title: "Дата и время")
                            ModernDateTimePicker(selection: $draft.date)
                        }
                    }
                    ForEach(Array(draft.assumptions.enumerated()), id: \.offset) { _, text in
                        Text(text).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    if let error = error ?? photo.error ?? model.storageError {
                        Text(error).font(.system(size: 11)).foregroundStyle(Palette.orange)
                    }
                }.padding(.bottom, 8).disabled(analyzing)
            }
            if analyzing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Оцениваю напиток на этом Mac…").font(.system(size: 12))
                    Spacer()
                    Button("Остановить") { cancelAnalysis() }.buttonStyle(.bordered)
                }.padding(.top, 12)
            }
            HStack(spacing: 12) {
                Button("Отмена") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button(draft.original == nil ? "Сохранить в дневник" : "Сохранить изменения") {
                    guard let meal = draft.meal else { return }
                    do { try model.saveDrink(meal, photoChange: photo.change); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButton()).disabled(draft.meal == nil || model.storageError != nil || photo.busy || analyzing)
            }.padding(.top, 16)
        }.padding(26).frame(width: 630, height: 680).background(Palette.background)
            .disclosureGroupStyle(ExpandableSectionStyle())
            .onAppear {
                guard !loadedExistingPhoto else { return }; loadedExistingPhoto = true
                if let url = model.repository.photoURL(draft.original?.photoFilename) { photo.load(url, replacing: false) }
            }
            .onDisappear { photoPanel?.cancel(nil); photoPanel = nil; photo.cancel(); cancelAnalysis() }
            .sheet(isPresented: $showLabelScanner) {
                LabelScannerView(unit: .milliliters, onCancel: { showLabelScanner = false }) { nutrients, unit in
                    guard unit == .milliliters else {
                        error = "На фото значения на 100 г. Для напитка нужны данные на 100 мл; без плотности их нельзя приравнять."
                        showLabelScanner = false; return
                    }
                    apply(nutrients); draft.isEstimate = false; draft.assumptions = []; error = nil
                    showLabelScanner = false
                }
            }
            .sheet(isPresented: $showProducts) {
                ProductPicker(initialGrams: draft.volume, unit: .milliliters) { product, volume in draft.choose(product, volume: volume) }
            }
            .sheet(item: $savingProduct) { product in ProductEditor(product: product) }
    }
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Palette.mint.opacity(0.5))
                    if let preview = photo.preview {
                        Image(nsImage: preview).resizable().scaledToFit().padding(4)
                    } else {
                        Image(systemName: "camera").font(.system(size: 26)).foregroundStyle(Palette.blue)
                    }
                }.frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(photo.preview == nil ? "Фото напитка не добавлено" : "Фотография напитка")
                VStack(alignment: .leading, spacing: 9) {
                    Button(photo.preview == nil ? "Добавить фото напитка" : "Заменить фото напитка") { choosePhoto() }
                        .buttonStyle(.bordered).disabled(photo.busy)
                    if photo.busy { ProgressView().controlSize(.small) }
                    else if photo.data != nil || (draft.original?.photoFilename != nil && !photo.removed) {
                        Button("Убрать фото") { photo.remove() }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                    }
                    Text("Фото сохранится в дневнике. JPEG, PNG, HEIC · до 40 МБ.")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }
            if photo.data != nil {
                TextField("Добавки: молоко, сахар, сироп…", text: $additions).inputSurface()
                    .accessibilityLabel("Добавки к напитку")
                Button("Оценить напиток по фото · бесплатно") { analyzePhoto() }
                    .buttonStyle(.bordered).disabled(photo.busy || Numbers.parse(draft.volume).map(Numbers.validWeight) != true)
                Text("По внешнему виду нельзя точно узнать количество сахара и добавок. Проверь оценку перед сохранением.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Button { showLabelScanner = true } label: { Label("БЖУ с фото упаковки", systemImage: "text.viewfinder") }
                .buttonStyle(.bordered)
        }.padding(16).background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
    private func choosePhoto() {
        guard photoPanel == nil else { return }
        let panel = NSOpenPanel()
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Выберите фотографию напитка"
        panel.prompt = "Добавить фото"
        photoPanel = panel
        DispatchQueue.main.async {
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                Task { @MainActor in
                    photoPanel = nil
                    if response == .OK, let url = panel.url { photo.load(url) }
                }
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
        }
    }
    private func apply(_ nutrients: Nutrients) {
        draft.calories = Numbers.input(nutrients.calories); draft.protein = Numbers.input(nutrients.protein)
        draft.fat = Numbers.input(nutrients.fat); draft.carbs = Numbers.input(nutrients.carbs)
    }
    private func analyzePhoto() {
        guard let data = photo.data, let volume = Numbers.parse(draft.volume), Numbers.validWeight(volume) else { return }
        cancelAnalysis(); model.coach.cancel(); analyzing = true; error = nil
        let token = analysisToken
        let notes = draft.name + ". " + additions
        analysisTask = Task {
            do {
                let result = try await OllamaService().analyzeDrink(jpeg: data, volume: volume, notes: notes)
                try Task.checkCancellation()
                guard token == analysisToken else { return }
                draft.name = result.name; apply(result.per100ml)
                draft.isEstimate = true; draft.assumptions = result.assumptions
            } catch {
                guard token == analysisToken, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            if token == analysisToken { analyzing = false; analysisTask = nil }
        }
    }
    private func cancelAnalysis() {
        analysisToken = UUID(); analysisTask?.cancel(); analysisTask = nil; analyzing = false
    }

}
