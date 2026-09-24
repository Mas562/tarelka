import AppKit
import SwiftUI
import NutritionCore
import UniformTypeIdentifiers
import Combine
import WidgetKit

enum Screen: Hashable { case newMeal, diary, products, day, week, coach, recipes, settings }
enum WeightMode: String, CaseIterable { case portion = "Общий вес порции", ingredients = "Вес каждого ингредиента" }

struct IngredientDraft: Identifiable {
    var id = UUID()
    var name = ""
    var grams = ""
    var calories = ""
    var protein = ""
    var fat = ""
    var carbs = ""
    var source: NutritionSource?
    var sourceName: String?
    var lookupQuery = ""
    init() {}
    init(_ ingredient: Ingredient) {
        id = ingredient.id; name = ingredient.name; source = ingredient.source; sourceName = ingredient.name
        grams = Numbers.input(ingredient.grams); calories = Numbers.input(ingredient.per100.calories)
        protein = Numbers.input(ingredient.per100.protein); fat = Numbers.input(ingredient.per100.fat)
        carbs = Numbers.input(ingredient.per100.carbs)
    }
    var ingredient: Ingredient? {
        guard let g = Numbers.parse(grams), let c = Numbers.parse(calories),
              let p = Numbers.parse(protein), let f = Numbers.parse(fat), let b = Numbers.parse(carbs)
        else { return nil }
        var result = Ingredient(id: id, name: name, grams: g, per100: Nutrients(calories: c, protein: p, fat: f, carbs: b))
        if sourceName == name, source?.per100 == result.per100 { result.source = source }
        return result.isValid ? result : nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .day
    @Published var meals: [Meal] = []
    @Published var photoData: Data? {
        didSet { photoPreview = photoData.flatMap { NSImage(data: $0) } }
    }
    @Published private(set) var photoPreview: NSImage?
    @Published var weight = ""
    @Published var weightMode = WeightMode.portion
    @Published var notes = ""
    @Published var dishName = ""
    @Published var kind = MealKind.suggested()
    @Published var mealDate = Date()
    @Published var drafts: [IngredientDraft] = []
    @Published var assumptions: [String] = []
    @Published var clarificationQuestions: [MealClarification] = []
    @Published var clarificationAnswers: [String: String] = [:]
    var hasClarificationAnswers: Bool {
        !MealClarifications.answerNotes(questions: clarificationQuestions, answers: clarificationAnswers).isEmpty
    }
    func skipClarifications() { clarificationQuestions = []; clarificationAnswers = [:] }
    @Published var hasResult = false
    @Published var isEstimate = false
    @Published var isAnalyzing = false
    @Published var hasKey = false
    @Published var modelName = OpenAIService.defaultModel
    @Published var provider = RecognitionProvider.local {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "recognitionProvider") }
    }
    let localSetup = LocalSetupModel()
    let coachSetup = LocalSetupModel(role: .coach)
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var selectedDay = Date()
    @Published var editingID: UUID?
    @Published var storageError: String?
    @Published var drinkEditor: DrinkDraft?
    let repository: MealRepository
    let personal: PersonalStore
    let coach: CoachStore
    let reminders: ReminderStore
    let recipes = RecipeStore()
    private var analysisTask: Task<Void, Never>?
    private var requestID = UUID()
    private var personalSubscription: AnyCancellable?
    private let publishesWidget: Bool

    init(directory suppliedDirectory: URL? = nil) {
        publishesWidget = suppliedDirectory == nil && ProcessInfo.processInfo.environment["TARELKA_DATA_DIR"] == nil
        let directory: URL
        if let suppliedDirectory { directory = suppliedDirectory }
        else if let override = ProcessInfo.processInfo.environment["TARELKA_DATA_DIR"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tarelka", isDirectory: true)
        }
        repository = MealRepository(directory: directory)
        personal = PersonalStore(directory: directory)
        coach = CoachStore(directory: directory)
        reminders = ReminderStore(directory: directory)
        do { meals = try repository.load() }
        catch { storageError = "Не удалось открыть дневник. Существующий файл сохранён: \(error.localizedDescription)" }
        hasKey = Keychain.containsKey()
        modelName = UserDefaults.standard.string(forKey: "visionModel") ?? OpenAIService.defaultModel
        provider = RecognitionProvider.restored(UserDefaults.standard.string(forKey: "recognitionProvider"))
        personalSubscription = personal.$data.dropFirst().sink { [weak self] _ in
            self?.reloadWidget()
        }
        reloadWidget()
    }
    func reloadWidget() {
        guard publishesWidget, storageError == nil, self.personal.storageError == nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TodaySnapshotStore.widgetKind)
    }
    var recentMeals: [Meal] {
        var seen = Set<String>()
        return meals.filter { meal in
            let key = "\(meal.isDrink)|\(meal.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\(meal.weight)"
            return seen.insert(key).inserted
        }.prefix(5).map { $0 }
    }
    func repeatMeal(_ original: Meal) {
        guard storageError == nil else { return }
        let repeated = Meal(date: Date(), kind: .suggested(), name: original.name, weight: original.weight,
                            ingredients: original.ingredients, notes: original.notes,
                            assumptions: original.assumptions, isEstimate: original.isEstimate)
        do {
            var updated = meals
            updated.append(repeated); updated.sort { $0.date > $1.date }
            try repository.save(updated)
            meals = updated; selectedDay = repeated.date
            notice = original.isDrink ? "Напиток добавлен повторно." : "Блюдо добавлено повторно."
            reloadWidget()
        } catch { errorMessage = "Не удалось повторить запись: \(error.localizedDescription)" }
    }
    var parsedWeight: Double? {
        if weightMode == .ingredients && hasResult {
            guard !drafts.isEmpty else { return nil }
            let values = drafts.compactMap { Numbers.parse($0.grams) }
            guard values.count == drafts.count, values.allSatisfy({ $0 > 0 }) else { return nil }
            let sum = values.reduce(0, +)
            return Numbers.validWeight(sum) ? sum : nil
        }
        guard let value = Numbers.parse(weight), Numbers.validWeight(value) else { return nil }
        return value
    }
    var ingredients: [Ingredient] { drafts.compactMap(\.ingredient) }
    var allIngredientsValid: Bool { !drafts.isEmpty && ingredients.count == drafts.count }
    var total: Nutrients { NutritionMath.total(ingredients) }
    var ingredientWeight: Double { ingredients.reduce(0) { $0 + $1.grams } }
    var weightMatches: Bool { parsedWeight.map { abs(ingredientWeight - $0) <= 0.1 } ?? false }
    var canSave: Bool {
        hasResult && allIngredientsValid && weightMatches && !dishName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isAnalyzing && !hasClarificationAnswers && storageError == nil
    }
    var hasDraft: Bool { photoData != nil || hasResult || !weight.isEmpty || !notes.isEmpty }
    func meals(on date: Date) -> [Meal] { meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    func total(on date: Date) -> Nutrients { meals(on: date).reduce(Nutrients()) { $0 + $1.total } }

    func binding(for draft: IngredientDraft) -> Binding<IngredientDraft> {
        Binding(get: { [weak self] in self?.drafts.first { $0.id == draft.id } ?? draft },
                set: { [weak self] value in
                    guard let self, let index = self.drafts.firstIndex(where: { $0.id == draft.id }) else { return }
                    self.drafts[index] = value
                })
    }
    func beginNewMeal(at date: Date = Date()) {
        guard editingID == nil, !hasDraft else { return }
        mealDate = date; kind = .suggested(at: date)
    }
    func refreshNewMealDate(at date: Date = Date()) {
        guard editingID == nil, !hasResult else { return }
        mealDate = date; kind = .suggested(at: date)
    }
    func choosePhoto() {
        guard !isAnalyzing else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Выберите фото блюда"
        panel.prompt = "Добавить фото"
        if panel.runModal() == .OK, let url = panel.url { importPhoto(url) }
    }
    func importPhoto(_ url: URL) {
        guard !isAnalyzing else { return }
        do { setPhoto(try PhotoLoader.load(url: url)) }
        catch { errorMessage = error.localizedDescription }
    }
    func pastePhoto() {
        guard !isAnalyzing else { return }
        let board = NSPasteboard.general
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            do { setPhoto(try PhotoLoader.prepare(data)) }
            catch { errorMessage = error.localizedDescription }
        } else if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first, url.isFileURL {
            importPhoto(url)
        } else { errorMessage = "В буфере обмена нет фотографии. Скопируйте изображение или выберите файл." }
    }
    private func setPhoto(_ data: Data) {
        skipClarifications()
        photoData = data
        // A different photo invalidates prior recognition; it must never inherit an unrelated meal's result.
        hasResult = false; drafts = []; assumptions = []; dishName = ""; isEstimate = false
        weightMode = .portion
        errorMessage = nil; notice = nil
    }
    func removePhoto() {
        guard !isAnalyzing else { return }
        skipClarifications()
        photoData = nil
    }
    func startManual() {
        refreshNewMealDate()
        skipClarifications()
        let initialWeight = parsedWeight
        hasResult = true; isEstimate = false; assumptions = []
        weightMode = .ingredients
        if drafts.isEmpty {
            var draft = IngredientDraft()
            if let grams = initialWeight { draft.grams = Numbers.input(grams) }
            drafts = [draft]
        }
    }
    func rescale() {
        guard weightMode == .portion else { return }
        guard let target = parsedWeight, allIngredientsValid,
              let updated = try? NutritionMath.normalize(ingredients, to: target) else { return }
        drafts = updated.map(IngredientDraft.init)
    }
    func changeWeightMode(_ mode: WeightMode) {
        if mode == .portion, let sum = parsedWeight { weight = Numbers.input(sum) }
        weightMode = mode
    }
    func addProduct(_ product: SavedProduct, grams: Double, replacing id: UUID? = nil) {
        guard product.unit == .grams else { return }
        let draft = IngredientDraft(product.portion(grams: grams))
        if let id, let index = drafts.firstIndex(where: { $0.id == id }) { drafts[index] = draft }
        else {
            if drafts.count == 1, drafts[0].name.isEmpty, drafts[0].calories.isEmpty { drafts = [] }
            drafts.append(draft)
        }
        hasResult = true
        if product.caloriesFromMacros { isEstimate = true }
    }
    func applyCatalog(_ food: CatalogFood, grams: Double, replacing id: UUID? = nil) {
        let draft = IngredientDraft(food.ingredient(grams: grams))
        if let id {
            guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
            drafts[index] = draft
        } else {
            if drafts.count == 1, drafts[0].name.isEmpty, drafts[0].calories.isEmpty { drafts = [] }
            drafts.append(draft)
        }
        hasResult = true; isEstimate = true
    }
    func applyRecognizedComponents(_ components: [Ingredient], queries: [String], useCatalog: Bool? = nil) {
        let useCatalog = useCatalog ?? (UserDefaults.standard.object(forKey: "useFoodCatalog") as? Bool ?? true)
        drafts = components.enumerated().map { index, ingredient in
            var draft = IngredientDraft(ingredient)
            draft.lookupQuery = index < queries.count ? queries[index] : ingredient.name
            guard useCatalog else { return draft }
            let exactProducts = personal.data.products.filter {
                $0.unit == .grams && FoodCatalog.normalize($0.name) == FoodCatalog.normalize(ingredient.name)
            }
            if exactProducts.count == 1, let product = exactProducts.first {
                var saved = product.portion(grams: ingredient.grams)
                saved.source = product.source ?? NutritionSource(title: "Мои продукты", detail: product.name, per100: product.per100)
                return IngredientDraft(saved)
            }
            // A model's partial English query is only a suggestion. The user confirms preparation.
            draft.calories = ""; draft.protein = ""; draft.fat = ""; draft.carbs = ""
            return draft
        }
    }
    func analyze(refining: Bool = false) {
        refreshNewMealDate()
        guard !isAnalyzing, let photo = photoData, let grams = parsedWeight else { return }
        guard !refining || hasClarificationAnswers else { return }
        let selectedProvider = provider
        var key = ""
        if selectedProvider == .openAI {
            do {
                guard let saved = try Keychain.read(), !saved.isEmpty else {
                    screen = .settings; notice = "Для OpenAI нужен ключ. Можно выбрать бесплатный режим на Mac — фото и вес сохранены."
                    return
                }
                key = saved
            } catch { errorMessage = error.localizedDescription; return }
        }
        let context = MealClarifications.context(notes: notes, questions: clarificationQuestions, answers: clarificationAnswers)
        guard context.count <= 8000 else {
            errorMessage = "Уточнения слишком длинные. Сократи текст в поле «Что стоит учесть» и повтори расчёт."
            return
        }
        isAnalyzing = true; errorMessage = nil; notice = nil
        let token = UUID(); requestID = token
        let hadAnswers = hasClarificationAnswers
        let model = modelName
        analysisTask = Task {
            do {
                let result: FoodEstimate
                if selectedProvider == .local {
                    result = try await OllamaService().analyze(jpeg: photo, weight: grams, notes: context)
                } else {
                    result = try await OpenAIService().analyze(jpeg: photo, weight: grams, notes: context, key: key, model: model)
                }
                guard !Task.isCancelled, requestID == token else { return }
                let components = try result.normalizedIngredients(weight: grams)
                weight = Numbers.input(grams); weightMode = .portion
                dishName = result.dish_name
                applyRecognizedComponents(components, queries: result.ingredients.map { $0.lookup_query ?? $0.name })
                assumptions = result.assumptions; isEstimate = true; hasResult = true
                // Commit answers only with a successful result. Failure/cancel keeps the old calculation and answers.
                if hadAnswers { notes = context }
                clarificationAnswers = [:]
                clarificationQuestions = hadAnswers ? [] : MealClarifications.questions(
                    dish: result.dish_name, ingredients: components.map(\.name), assumptions: result.assumptions)
                if hadAnswers { notice = "Уточнения учтены. Проверь новый состав перед сохранением." }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                guard requestID == token else { return }
                if let urlError = error as? URLError {
                    errorMessage = urlError.code == .timedOut
                        ? "Распознавание заняло слишком много времени. Попробуйте ещё раз."
                        : (selectedProvider == .local ? LocalModelError.unavailable.localizedDescription : "Не удалось связаться с OpenAI. Проверьте интернет и доступ к сервису.")
                } else { errorMessage = error.localizedDescription }
                if let localError = error as? LocalModelError, localError == .unavailable || localError == .missingModel {
                    screen = .settings
                }
            }
            if requestID == token { isAnalyzing = false; analysisTask = nil }
        }
    }
    func cancelAnalysis() {
        requestID = UUID(); analysisTask?.cancel(); analysisTask = nil; isAnalyzing = false
    }
    func resetDraft() {
        cancelAnalysis()
        skipClarifications()
        photoData = nil; weight = ""; notes = ""; dishName = ""; kind = .suggested(); mealDate = Date()
        drafts = []; assumptions = []; hasResult = false; isEstimate = false; editingID = nil
        weightMode = .portion
        errorMessage = nil; notice = nil
    }
    func edit(_ meal: Meal) {
        if meal.isDrink { drinkEditor = DrinkDraft(meal: meal); return }
        resetDraft()
        editingID = meal.id; weight = Numbers.input(meal.weight); notes = meal.notes; dishName = meal.name
        kind = meal.kind; mealDate = meal.date; drafts = meal.ingredients.map(IngredientDraft.init)
        assumptions = meal.assumptions; hasResult = true; isEstimate = meal.isEstimate
        weightMode = .ingredients
        if let url = repository.photoURL(meal.photoFilename) {
            do { photoData = try Data(contentsOf: url) }
            catch { notice = "Фото записи недоступно. Данные о составе и калориях сохранены." }
        }
        screen = .newMeal
    }
    func saveMeal() {
        guard canSave, let grams = parsedWeight else { return }
        let previous = meals.first { $0.id == editingID }
        var newPhoto: String?
        do {
            if let photoData { newPhoto = try repository.savePhoto(photoData) }
            let meal = Meal(id: editingID ?? UUID(), date: mealDate, kind: kind,
                            name: dishName.trimmingCharacters(in: .whitespacesAndNewlines), weight: grams,
                            ingredients: ingredients, notes: notes, assumptions: assumptions,
                            isEstimate: isEstimate, photoFilename: newPhoto)
            var updated = meals.filter { $0.id != meal.id }
            updated.append(meal); updated.sort { $0.date > $1.date }
            try repository.save(updated)
            meals = updated
            reloadWidget()
            repository.removePhoto(previous?.photoFilename)
            selectedDay = meal.date
            resetDraft(); screen = .diary; notice = "Блюдо сохранено в дневник."
        } catch {
            repository.removePhoto(newPhoto)
            errorMessage = "Не удалось сохранить блюдо: \(error.localizedDescription)"
        }
    }
    func deleteMeal(_ meal: Meal) {
        guard storageError == nil else { return }
        let updated = meals.filter { $0.id != meal.id }
        do {
            try repository.save(updated); meals = updated
            reloadWidget()
            repository.removePhoto(meal.photoFilename)
            if editingID == meal.id { resetDraft() }
        } catch { errorMessage = "Не удалось удалить запись: \(error.localizedDescription)" }
    }
    func saveDrink(_ value: Meal, photoChange: DrinkPhotoChange = .unchanged) throws {
        guard storageError == nil, value.isDrink else { throw FoodError.invalidIngredient }
        try value.validate()
        let previous = meals.first { $0.id == value.id }
        var meal = value
        var newPhoto: String?
        do {
            switch photoChange {
            case .unchanged: meal.photoFilename = previous?.photoFilename ?? value.photoFilename
            case .remove: meal.photoFilename = nil
            case .replace(let data):
                newPhoto = try repository.savePhoto(data)
                meal.photoFilename = newPhoto
            }
            var updated = meals.filter { $0.id != meal.id }
            updated.append(meal); updated.sort { $0.date > $1.date }
            try repository.save(updated)
            meals = updated; selectedDay = meal.date; screen = .diary
            reloadWidget()
            if previous?.photoFilename != meal.photoFilename { repository.removePhoto(previous?.photoFilename) }
            notice = "Напиток сохранён в дневник."
        } catch {
            repository.removePhoto(newPhoto)
            throw error
        }
    }
    func saveSettings(key: String, model: String) -> Bool {
        do {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try Keychain.save(key) }
            let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanModel.isEmpty else { return false }
            modelName = cleanModel; UserDefaults.standard.set(cleanModel, forKey: "visionModel")
            hasKey = Keychain.containsKey(); notice = "Настройки сохранены."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func deleteKey() {
        do { try Keychain.delete(); hasKey = false; notice = "Ключ удалён из Связки ключей." }
        catch { errorMessage = error.localizedDescription }
    }
}
