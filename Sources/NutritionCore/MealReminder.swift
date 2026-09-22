import Foundation

public struct MealReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var hour: Int
    public var minute: Int
    public var enabled: Bool
    public init(id: UUID = UUID(), title: String, hour: Int, minute: Int = 0, enabled: Bool = true) {
        self.id = id; self.title = title; self.hour = hour; self.minute = minute; self.enabled = enabled
    }
    public var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 60 }
    public func notificationTime(leadMinutes: Int) -> DateComponents {
        let total = ((hour * 60 + minute - leadMinutes) % 1440 + 1440) % 1440
        return DateComponents(hour: total / 60, minute: total % 60)
    }
}
public struct ReminderPlan: Codable, Equatable, Sendable {
    public var enabled = false
    public var leadMinutes = 30
    public var meals = [MealReminder(title: "Завтрак", hour: 9), MealReminder(title: "Обед", hour: 14), MealReminder(title: "Ужин", hour: 19)]
    public init() {}
    public var isValid: Bool {
        [0, 15, 30, 60].contains(leadMinutes) && (1...8).contains(meals.count)
        && meals.allSatisfy(\.isValid) && Set(meals.map(\.id)).count == meals.count
        && (!enabled || meals.contains(where: \.enabled))
    }
}
