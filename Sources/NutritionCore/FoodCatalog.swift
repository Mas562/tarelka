import Foundation

public struct CatalogFood: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let per100: Nutrients
    public var sourceURL: URL { URL(string: "https://fdc.nal.usda.gov/food-details/\(id)/nutrients")! }
    public var source: NutritionSource { NutritionSource(title: "USDA SR Legacy · \(id)", detail: name, url: sourceURL.absoluteString, per100: per100) }
    public var displayName: String { FoodCatalog.localized(name) }
    public func ingredient(grams: Double, name customName: String? = nil) -> Ingredient {
        var value = Ingredient(name: customName ?? displayName, grams: grams, per100: per100)
        value.source = source
        return value
    }
}

/// A source applies only while its original per-100 values remain unchanged.
public struct NutritionSource: Codable, Equatable, Sendable {
    public var title: String
    public var detail: String
    public var url: String?
    public var per100: Nutrients
    public init(title: String, detail: String, url: String? = nil, per100: Nutrients) {
        self.title = title; self.detail = detail; self.url = url; self.per100 = per100
    }
}

public struct FoodCatalog: Sendable {
    public let foods: [CatalogFood]
    private let indexed: [(food: CatalogFood, text: String)]
    public static let shared: FoodCatalog = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tarelka_NutritionCore.bundle")
        let resource = bundled.flatMap(Bundle.init(url:))?.url(forResource: "usda-sr-legacy", withExtension: "json")
            ?? Bundle.module.url(forResource: "usda-sr-legacy", withExtension: "json")
        let values = resource.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([CatalogFood].self, from: $0) } ?? []
        return FoodCatalog(foods: values)
    }()
    public init(foods: [CatalogFood]) {
        self.foods = foods.filter { $0.per100.isValidPer100 }
        indexed = self.foods.map { food in
            let lower = " " + Self.normalize(food.name)
            let aliases = Self.terms.filter { lower.contains(" " + $0.0) }.map(\.1).joined(separator: " ")
            return (food, Self.normalize(food.name + " " + aliases))
        }
    }
    public func exact(_ query: String) -> CatalogFood? {
        let query = Self.normalize(query)
        guard !query.isEmpty else { return nil }
        let matches = foods.filter { Self.normalize($0.name) == query || Self.normalize($0.displayName) == query }
        return matches.count == 1 ? matches[0] : nil
    }
    public func search(_ query: String, limit: Int = 60) -> [CatalogFood] {
        let tokens = Self.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return Array(foods.prefix(limit)) }
        return indexed.compactMap { entry -> (CatalogFood, Int)? in
            let words = entry.text.split(separator: " ")
            let matched = tokens.allSatisfy { token in
                words.contains { $0 == token || (token.count >= 3 && $0.hasPrefix(token)) }
            }
            guard matched else { return nil }
            let exact = Self.normalize(entry.food.displayName) == Self.normalize(query) || Self.normalize(entry.food.name) == Self.normalize(query)
            return (entry.food, exact ? 0 : entry.food.name.count + Self.searchPenalty(entry.food.name))
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.prefix(limit).map(\.0)
    }
    public static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func searchPenalty(_ name: String) -> Int {
        let lower = name.lowercased()
        // Generic foods come before substitutes, offal and restaurant dishes.
        // They remain searchable, with their original description always visible.
        let brands = ["fast food", "restaurant", "kfc", "popeyes", "cracker barrel", "mcdonald", "burger king", "pillsbury", "kraft", "wendy", "subway"]
        if brands.contains(where: lower.contains) { return 1000 }
        if ["meatless", "imitation", "substitute"].contains(where: lower.contains) { return 800 }
        if ["liver", "giblets", "skin only", "heart"].contains(where: lower.contains) { return 200 }
        return 0
    }
    public static func localized(_ name: String) -> String {
        name.components(separatedBy: ", ").map { part in
            translations[part.lowercased()] ?? part
        }.joined(separator: " · ")
    }
    // Search aliases are category words, never evidence for automatically choosing a food.
    private static let terms: [(String, String)] = [
        ("chicken", "курица куриная куриный куриное курицу"), ("turkey", "индейка индейки"),
        ("beef", "говядина говяжья"), ("pork", "свинина свиная"), ("lamb", "баранина"), ("rabbit", "кролик"),
        ("breast", "грудка филе"), ("thigh", "бедро"), ("wing", "крыло крылья"), ("liver", "печень"),
        ("meat only", "без кожи мясо"), ("meat and skin", "с кожей"), ("raw", "сырая сырой сырое сырого"),
        ("fried", "жареная жареный жареное жаренная жаренную"), ("roasted", "запеченная запеченный запеченное"),
        ("boiled", "вареный вареная отварной"), ("cooked", "готовый готовая готовое вареный вареная"),
        ("stewed", "тушеная тушеный"), ("breaded", "панировка"), ("batter", "кляр"),
        ("rice", "рис рисовая"), ("buckwheat", "гречка гречневая"), ("oat", "овсянка овес овсяная"),
        ("pasta", "макароны паста"), ("spaghetti", "спагетти макароны"), ("barley", "перловка ячмень"),
        ("millet", "пшено пшенная"), ("quinoa", "киноа"), ("bread", "хлеб"), ("rye", "ржаной рожь"),
        ("wheat", "пшеница пшеничный"), ("flour", "мука"), ("egg", "яйцо яйца яичный"),
        ("milk", "молоко молочный"), ("yogurt", "йогурт"), ("cheese", "сыр"), ("cottage", "творог"),
        ("cream", "сливки"), ("sour cream", "сметана"), ("butter", "масло сливочное"), ("kefir", "кефир"),
        ("potato", "картофель картошка"), ("tomato", "помидор томат"), ("cucumber", "огурец огурцы"),
        ("carrot", "морковь"), ("onion", "лук"), ("garlic", "чеснок"), ("cabbage", "капуста"),
        ("broccoli", "брокколи"), ("cauliflower", "цветная капуста"), ("pepper", "перец"),
        ("lettuce", "салат"), ("spinach", "шпинат"), ("beet", "свекла"), ("zucchini", "кабачок"),
        ("eggplant", "баклажан"), ("mushroom", "грибы шампиньоны"), ("pumpkin", "тыква"),
        ("apple", "яблоко яблоки"), ("banana", "банан"), ("orange", "апельсин"), ("pear", "груша"),
        ("peach", "персик"), ("grape", "виноград"), ("lemon", "лимон"), ("kiwi", "киви"),
        ("strawberr", "клубника"), ("raspberr", "малина"), ("blueberr", "черника"),
        ("cherr", "вишня черешня"), ("watermelon", "арбуз"), ("avocado", "авокадо"),
        ("salmon", "лосось семга"), ("tuna", "тунец"), ("cod", "треска"), ("herring", "сельдь"),
        ("shrimp", "креветки"), ("fish", "рыба рыбный"), ("trout", "форель"), ("mackerel", "скумбрия"),
        ("sausage", "сосиска сосиски колбаса"), ("frankfurter", "сосиски"), ("ham", "ветчина"),
        ("oil", "масло растительное"), ("olive", "оливковое оливки"), ("sunflower", "подсолнечное семечки"),
        ("sugar", "сахар"), ("honey", "мед"), ("salt", "соль"), ("chocolate", "шоколад"),
        ("cookie", "печенье"), ("cake", "торт кекс"), ("almond", "миндаль"), ("walnut", "грецкий орех"),
        ("peanut", "арахис"), ("cashew", "кешью"), ("nut", "орехи"), ("bean", "фасоль"),
        ("lentil", "чечевица"), ("chickpea", "нут"), ("pea", "горох"), ("corn", "кукуруза"),
        ("tofu", "тофу"), ("soy", "соя соевый"), ("mayonnaise", "майонез"), ("ketchup", "кетчуп"),
        ("coffee", "кофе"), ("tea", "чай"), ("juice", "сок"), ("water", "вода"),
        ("canned", "консервы консервированный"), ("frozen", "замороженный"), ("dried", "сушеный сухой")
    ]
    private static let translations: [String: String] = [
        "chicken":"Курица", "broilers or fryers":"бройлер", "breast":"грудка", "meat only":"без кожи",
        "meat and skin":"с кожей", "skin only":"кожа", "raw":"сырое", "cooked":"готовое",
        "meatless":"растительный заменитель, без мяса", "liver":"печень", "giblets":"потроха",
        "all classes":"все категории", "pan-fried":"жареное на сковороде", "neck":"шея",
        "meat and skin and breading":"мясо с кожей и панировкой", "skin and breading":"кожа и панировка",
        "fried":"жареное", "roasted":"запечённое", "stewed":"тушёное", "boiled":"варёное",
        "batter":"в кляре", "flour":"в мучной панировке", "breaded":"в панировке",
        "thigh":"бедро", "wing":"крыло", "drumstick":"голень", "leg":"ножка", "back":"спинка",
        "turkey":"Индейка", "beef":"Говядина", "pork":"Свинина", "lamb":"Баранина",
        "rice":"Рис", "white":"белый", "brown":"бурый", "long-grain":"длиннозёрный", "unenriched":"необогащённый",
        "enriched":"обогащённый", "regular":"обычный", "buckwheat":"Гречка", "buckwheat groats":"Гречневая крупа",
         "oats":"Овёс", "pasta":"Макароны", "spaghetti":"Спагетти",
        "without added salt":"без добавления соли", "with salt":"с солью", "without salt":"без соли",
        "egg":"Яйцо", "whole":"цельное", "fresh":"свежее", "hard-boiled":"вкрутую", "scrambled":"болтунья",
        "milk":"Молоко", "cheese":"Сыр", "yogurt":"Йогурт", "plain":"без добавок", "low fat":"нежирное",
        "cheddar":"чеддер", "gouda":"гауда", "mozzarella":"моцарелла", "cottage":"творожный",
        "butter":"Масло сливочное", "salted":"солёное", "unsalted":"несолёное", "oil":"Масло",
        "olive":"оливковое", "salad or cooking":"для салата / готовки", "sunflower":"подсолнечное",
        "bread":"Хлеб", "wheat":"пшеничный", "rye":"ржаной", "whole-wheat":"цельнозерновой",
        "potatoes":"Картофель", "flesh and skin":"с кожурой", "flesh":"мякоть", "baked":"печёное",
        "tomatoes":"Помидоры", "red":"красный", "ripe":"спелый", "cucumber":"Огурец", "with peel":"с кожурой",
        "carrots":"Морковь", "onions":"Лук", "cabbage":"Капуста", "broccoli":"Брокколи", "spinach":"Шпинат",
        "apples":"Яблоки", "bananas":"Бананы", "pears":"Груши", "oranges":"Апельсины", "avocados":"Авокадо",
        "fish":"Рыба", "salmon":"лосось", "tuna":"тунец", "cod":"треска", "atlantic":"атлантический",
        "dry heat":"сухой нагрев", "wild":"дикий", "farmed":"фермерский", "canned":"консервированное",
        "drained solids":"без жидкости", "frozen":"замороженное", "dried":"сушёное", "nuts":"Орехи",
        "almonds":"миндаль", "walnuts":"грецкие", "peanuts":"Арахис", "sugars":"Сахар", "granulated":"песок",
        "honey":"Мёд", "beverages":"Напитки", "water":"Вода", "tap":"водопроводная", "drinking":"питьевая"
    ]
}
