import Foundation
import Testing
import CoreText
import ImageIO
@testable import NutritionCore

struct LabelAndWeekTests {
    @Test func appleVisionReadsRussianLabelImage() async throws {
        let context = try #require(CGContext(data: nil, width: 1800, height: 1300, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1300))
        let rows = ["Пищевая ценность на 100 мл", "Белки 0,5 г", "Жиры 0,1 г", "Углеводы 11 г", "Энергетическая ценность", "193 кДж / 46 ккал"]
        for (index, text) in rows.enumerated() {
            let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 64, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)])
            context.textPosition = CGPoint(x: 90, y: 1150 - index * 175)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        // The same generated fixture is used for the manual app scan. It contains no user data.
        try (data as Data).write(to: URL(fileURLWithPath: "/private/tmp/Tarelka-label-qa.png"), options: .atomic)
        let scan = try await NutritionLabelReader.read(data as Data)
        #expect(scan.unit == .milliliters)
        #expect(scan.calories == 46 && scan.protein == 0.5 && scan.fat == 0.1 && scan.carbs == 11, "OCR text: \(scan.text)")
    }

    @Test func russianLabelWithDecimalCommasAndKilojoules() {
        let scan = NutritionLabelParser.parse(text: "Пищевая ценность на 100 г\nБелки — 12,5 г\nЖиры 9,2 г\nУглеводы 3,1 г\nЭнергетическая ценность 600 кДж / 144 ккал")
        #expect(scan.unit == .grams && scan.foundCount == 4)
        #expect(scan.protein == 12.5 && scan.fat == 9.2 && scan.carbs == 3.1 && scan.calories == 144)
    }

    @Test func englishDrinkDoesNotConfuseSugarSaturatedFatAndPercentages() {
        let scan = NutritionLabelParser.parse(text: "Nutrition per 100 ml\nCalories 46\nProtein 0.5g\nTotal Fat 0.1g 1%\nSaturated fat 0g\nTotal Carbohydrate 11g\nSugars 10g")
        #expect(scan.unit == .milliliters && scan.foundCount == 4)
        #expect(scan.protein == 0.5 && scan.fat == 0.1 && scan.carbs == 11 && scan.calories == 46)
    }

    @Test func inlineParagraphAndSplitTableRows() {
        let paragraph = NutritionLabelParser.parse(text: "На 100 г: белки 8,0 г, жиры 2,5 г, углеводы 15 г, энергетическая ценность 115 ккал.")
        #expect(paragraph.foundCount == 4 && paragraph.fat == 2.5)
        let blocks = [LabelTextBlock("на 100 г", rect: CGRect(x: 0.1, y: 0.85, width: 0.4, height: 0.04)),
                      LabelTextBlock("Белки", rect: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.04)),
                      LabelTextBlock("12,5 г", rect: CGRect(x: 0.7, y: 0.701, width: 0.2, height: 0.04)),
                      LabelTextBlock("Жиры", rect: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.04)),
                      LabelTextBlock("2 г", rect: CGRect(x: 0.7, y: 0.599, width: 0.2, height: 0.04))]
        let table = NutritionLabelParser.parse(blocks: blocks)
        #expect(table.protein == 12.5 && table.fat == 2 && table.carbs == nil)
    }

    @Test func unknownServingAndAmbiguousColumnsAreNotGuessed() {
        for basis in ["На порцию 30 г", "", "Per serving (250ml)", "Масса нетто 100 г\nНа порцию 30 г", "Net weight 100 g\nPer serving (30g)"] {
            let scan = NutritionLabelParser.parse(text: "\(basis)\nБелки 10 г\nЖиры 2 г\nУглеводы 3 г\n100 ккал")
            #expect(scan.unit == nil && scan.foundCount == 0)
        }
        let columns = NutritionLabelParser.parse(text: "На 100 г / на порцию 30 г\nБелки 10 3\nЖиры 2 0,6\nУглеводы 20 6\nЭнергетическая ценность 150 ккал 45 ккал")
        #expect(columns.foundCount == 0)
        let invalid = NutritionLabelParser.parse(text: "На 100 г\nБелки менее 0,5 г\nЖиры 120 г\nУглеводы 1–2 г\nЭнергетическая ценность 1800 кДж")
        #expect(invalid.foundCount == 0)
    }

    @Test func zeroIsDifferentFromMissingAndConflictingValues() {
        let scan = NutritionLabelParser.parse(text: "На 100 мл\nБелки 0 г\nЖиры 0 г\nУглеводы 0 г\n0 ккал")
        #expect(scan.foundCount == 4 && scan.calories == 0)
        let conflict = NutritionLabelParser.parse(text: "На 100 г\nБелки 10 г\nБелки 20 г\nЖиры 0 г")
        #expect(conflict.protein == nil && conflict.fat == 0 && conflict.carbs == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!; return calendar
    }
    private func date(_ day: Int, month: Int = 9, year: Int = 2026, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func meal(_ date: Date, calories: Double, unit: PortionUnit = .grams) -> Meal {
        Meal(date: date, kind: .lunch, name: "Тест", weight: 100,
             ingredients: [Ingredient(name: "Тест", amount: 100, unit: unit, per100: Nutrients(calories: calories, protein: 10))])
    }

    @Test func weekUsesMondayBoundariesAndExcludesFutureAndOutsideRecords() {
        let meals = [meal(date(6), calories: 900), meal(date(7, hour: 0), calories: 100), meal(date(9), calories: 200),
                     meal(date(10), calories: 300), meal(date(14, hour: 0), calories: 500)]
        let report = WeekSummary(containing: date(9), now: date(9), meals: meals, personal: PersonalData(), calendar: calendar)
        #expect(report.start == date(7, hour: 0) && report.end == date(14, hour: 0))
        #expect(report.days.count == 7 && report.elapsedDays == 3 && report.loggedDays.count == 2)
        #expect(report.total.calories == 300 && report.average?.calories == 150)
        #expect(report.days[1].hasEntries == false && report.days[3].isFuture)
        let year = WeekSummary(containing: date(1, month: 1, year: 2027), now: date(4, month: 1, year: 2027), meals: [], personal: PersonalData(), calendar: calendar)
        #expect(year.start == date(28, month: 12, hour: 0) && year.end == date(4, month: 1, year: 2027, hour: 0))
    }

    @Test func weekIncludesDrinksAndOnlyKnownActivityWithCorrectBudget() {
        var personal = PersonalData(); personal.manualTarget = 2500
        personal.activity = [DailyActivity(day: "2026-09-07", activeCalories: 300, updatedAt: date(7), source: .manual),
                             DailyActivity(day: "2026-09-08", activeCalories: 0, updatedAt: date(8), source: .appleHealth),
                             DailyActivity(day: "2026-09-10", activeCalories: 400, updatedAt: date(10), source: .manual)]
        let meals = [meal(date(7), calories: 500), meal(date(7), calories: 115, unit: .milliliters)]
        let report = WeekSummary(containing: date(9), now: date(9), meals: meals, personal: personal, calendar: calendar)
        #expect(report.total.calories == 615 && report.average?.calories == 615)
        #expect(report.drinkCount == 1 && report.days[0].drinkMilliliters == 100)
        #expect(report.totalActivity == 300 && report.activityDays.count == 2)
        #expect(report.days[0].budget?.remaining == 2185)
        #expect(report.days[1].activeCalories == 0 && report.days[2].activeCalories == nil)
        #expect(report.days[2].budget?.awaitingActivity == true && report.days[3].budget == nil)
        personal.budgetSettings = BudgetSettings(accounting: .estimated)
        let estimated = WeekSummary(containing: date(9), now: date(9), meals: meals, personal: personal, calendar: calendar)
        #expect(estimated.days[0].budget?.target == 2500)
    }

    @Test func emptyWeekHasNoAverageAndWaterIsAnExplicitZero() {
        let empty = WeekSummary(containing: date(9), now: date(9), meals: [], personal: PersonalData(), calendar: calendar)
        #expect(empty.average == nil && empty.totalActivity == nil && empty.loggedDays.isEmpty)
        let water = WeekSummary(containing: date(9), now: date(9), meals: [meal(date(7), calories: 0, unit: .milliliters)], personal: PersonalData(), calendar: calendar)
        #expect(water.average?.calories == 0 && water.loggedDays.count == 1)
    }
}
