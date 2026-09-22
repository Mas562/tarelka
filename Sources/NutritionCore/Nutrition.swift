import Foundation

public enum FoodError: LocalizedError {
    case invalidWeight, invalidIngredient, mismatchedWeight, mixedUnits, noFood, invalidResponse
    case requestFailed(Int), unauthorized, rateLimited, incomplete, refused, storageVersion

    public var errorDescription: String? {
        switch self {
        case .invalidWeight: return "Введите вес готовой еды от 0,1 до 20 000 г, без посуды."
        case .invalidIngredient: return "Проверьте состав: нужны название, положительный вес и корректные калории и БЖУ на 100 г. Сумма БЖУ не должна превышать 100 г."
        case .mismatchedWeight: return "Сумма весов ингредиентов отличается от веса порции. Скорректируйте веса или распределите вес порции пропорционально."
        case .mixedUnits: return "Граммы и миллилитры нельзя складывать в одну порцию. Добавьте напиток отдельной записью."
        case .noFood: return "На фото не удалось определить блюдо. Попробуйте снять еду крупнее или заполните состав вручную."
        case .invalidResponse: return "Не удалось прочитать состав блюда. Попробуйте ещё раз или заполните его вручную."
        case .requestFailed(let code): return "Сервис распознавания вернул ошибку \(code). Повторите попытку позже."
        case .unauthorized: return "Ключ API не принят. Проверьте ключ в настройках."
        case .rateLimited: return "Достигнут лимит API или закончился баланс. Проверьте биллинг OpenAI и попробуйте позже."
        case .incomplete: return "Сервис не завершил распознавание. Попробуйте ещё раз."
        case .refused: return "Сервис не смог обработать это фото. Попробуйте другой снимок блюда."
        case .storageVersion: return "Дневник создан более новой версией приложения. Обновите «Тарелку», чтобы открыть его."
        }
    }
}

public enum Numbers {
    /// Explicitly accepts either Russian decimal commas or decimal points; never parses a prefix.
    public static func parse(_ string: String) -> Double? {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: #"^\d+(?:\.\d*)?$"#, options: .regularExpression) != nil,
              let value = Double(clean), value.isFinite else { return nil }
        return value
    }
    public static func validWeight(_ value: Double) -> Bool {
        value.isFinite && value >= 0.1 && value <= 20_000
    }
    public static func display(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0...decimals)))
    }
    public static func input(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
    }
}

public struct Nutrients: Codable, Equatable, Sendable {
    public var calories: Double
    public var protein: Double
    public var fat: Double
    public var carbs: Double

    public init(calories: Double = 0, protein: Double = 0, fat: Double = 0, carbs: Double = 0) {
        self.calories = calories; self.protein = protein; self.fat = fat; self.carbs = carbs
    }
    public var isValidPer100: Bool {
        [calories, protein, fat, carbs].allSatisfy { $0.isFinite && $0 >= 0 }
        && calories <= 1000 && protein <= 100 && fat <= 100 && carbs <= 100
        && protein + fat + carbs <= 100.5
    }
    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(calories: calories * factor, protein: protein * factor, fat: fat * factor, carbs: carbs * factor)
    }
    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                  fat: lhs.fat + rhs.fat, carbs: lhs.carbs + rhs.carbs)
    }
}

public enum PortionUnit: String, Codable, CaseIterable, Sendable {
    case grams, milliliters
    public var symbol: String { self == .grams ? "г" : "мл" }
    public var basis: String { "100 \(symbol)" }
}

public struct Ingredient: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Double
    public var unit: PortionUnit
    /// Compatibility accessor for the food-only weighing and recognition flow.
    public var grams: Double {
        get { amount }
        set { amount = newValue }
    }
    public var per100: Nutrients
    public var source: NutritionSource?
    public init(id: UUID = UUID(), name: String, grams: Double, per100: Nutrients) {
        self.init(id: id, name: name, amount: grams, unit: .grams, per100: per100)
    }
    public init(id: UUID = UUID(), name: String, amount: Double, unit: PortionUnit, per100: Nutrients) {
        self.id = id; self.name = name; self.amount = amount; self.unit = unit; self.per100 = per100
    }
    private enum CodingKeys: String, CodingKey { case id, name, grams, amount, unit, per100, source }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        unit = try values.decodeIfPresent(PortionUnit.self, forKey: .unit) ?? .grams
        amount = try values.decodeIfPresent(Double.self, forKey: .amount) ?? values.decode(Double.self, forKey: .grams)
        per100 = try values.decode(Nutrients.self, forKey: .per100)
        source = try values.decodeIfPresent(NutritionSource.self, forKey: .source)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        // Keep ordinary food records readable by the original journal format.
        try values.encode(amount, forKey: unit == .grams ? .grams : .amount)
        if unit != .grams { try values.encode(unit, forKey: .unit) }
        try values.encode(per100, forKey: .per100)
        try values.encodeIfPresent(source, forKey: .source)
    }
    public var total: Nutrients { per100.scaled(by: amount / 100) }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && name.count <= 300 && grams.isFinite && grams > 0 && grams <= 20_000 && per100.isValidPer100
    }
}

public enum NutritionMath {
    public static func total(_ ingredients: [Ingredient]) -> Nutrients {
        ingredients.reduce(Nutrients()) { $0 + $1.total }
    }
    public static func normalize(_ ingredients: [Ingredient], to weight: Double) throws -> [Ingredient] {
        guard Numbers.validWeight(weight) else { throw FoodError.invalidWeight }
        guard !ingredients.isEmpty, ingredients.allSatisfy(\.isValid) else { throw FoodError.invalidIngredient }
        guard ingredients.allSatisfy({ $0.unit == ingredients[0].unit }) else { throw FoodError.mixedUnits }
        let sum = ingredients.reduce(0) { $0 + $1.grams }
        guard sum.isFinite, sum > 0 else { throw FoodError.invalidIngredient }
        return ingredients.map {
            var value = $0
            value.grams = $0.grams * weight / sum
            return value
        }
    }
    public static func validate(_ ingredients: [Ingredient], weight: Double) throws {
        guard Numbers.validWeight(weight) else { throw FoodError.invalidWeight }
        guard !ingredients.isEmpty, ingredients.allSatisfy(\.isValid) else { throw FoodError.invalidIngredient }
        guard ingredients.allSatisfy({ $0.unit == ingredients[0].unit }) else { throw FoodError.mixedUnits }
        guard abs(ingredients.reduce(0) { $0 + $1.grams } - weight) <= 0.1 else { throw FoodError.mismatchedWeight }
    }
}

public enum MealKind: String, Codable, CaseIterable, Sendable {
    case breakfast = "Завтрак", lunch = "Обед", dinner = "Ужин", snack = "Перекус"
    public var symbol: String {
        switch self { case .breakfast: return "sunrise"; case .lunch: return "sun.max"; case .dinner: return "moon"; case .snack: return "apple.logo" }
    }
    public static func suggested(at date: Date = Date()) -> MealKind {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}

public struct Meal: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: MealKind
    public var name: String
    public var weight: Double
    public var ingredients: [Ingredient]
    public var notes: String
    public var assumptions: [String]
    public var isEstimate: Bool
    public var photoFilename: String?
    public var total: Nutrients { NutritionMath.total(ingredients) }
    public var unit: PortionUnit { ingredients.first?.unit ?? .grams }
    public var isDrink: Bool { unit == .milliliters }

    public init(id: UUID = UUID(), date: Date, kind: MealKind, name: String, weight: Double,
                ingredients: [Ingredient], notes: String = "", assumptions: [String] = [],
                isEstimate: Bool = false, photoFilename: String? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.name = name; self.weight = weight
        self.ingredients = ingredients; self.notes = notes; self.assumptions = assumptions
        self.isEstimate = isEstimate; self.photoFilename = photoFilename
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FoodError.invalidIngredient }
        try NutritionMath.validate(ingredients, weight: weight)
    }
}

public struct FoodEstimate: Decodable, Sendable {
    public struct Component: Decodable, Sendable {
        public let name: String
        public let lookup_query: String?
        public let estimated_grams: Double
        public let calories_per_100g: Double
        public let protein_per_100g: Double
        public let fat_per_100g: Double
        public let carbs_per_100g: Double
    }
    public let is_food: Bool
    public let dish_name: String
    public let ingredients: [Component]
    public let assumptions: [String]

    public func normalizedIngredients(weight: Double) throws -> [Ingredient] {
        guard is_food else { throw FoodError.noFood }
        guard !dish_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dish_name.count <= 300, ingredients.count <= 30 else { throw FoodError.invalidResponse }
        return try NutritionMath.normalize(ingredients.map {
            Ingredient(name: $0.name, grams: $0.estimated_grams,
                       per100: Nutrients(calories: $0.calories_per_100g, protein: $0.protein_per_100g,
                                         fat: $0.fat_per_100g, carbs: $0.carbs_per_100g))
        }, to: weight)
    }
}
