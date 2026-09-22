import Foundation

/// A planning split within adult AMDR ranges, not an individually prescribed requirement.
/// Height, weight and activity enter through the existing daily energy budget.
public struct MacroTargets: Encodable, Equatable, Sendable {
    public let protein: Double
    public let fat: Double
    public let carbs: Double

    public init?(calories: Double) {
        guard calories.isFinite, calories > 0 else { return nil }
        protein = calories * 0.20 / 4
        fat = calories * 0.30 / 9
        carbs = calories * 0.50 / 4
    }
}

public extension DayBudget {
    var macroTargets: MacroTargets? { MacroTargets(calories: target) }
}

public struct MacroProgress: Equatable, Sendable {
    public let eaten: Double
    public let target: Double
    public init(eaten: Double, target: Double) {
        self.eaten = eaten.isFinite ? max(0, eaten) : 0
        self.target = target.isFinite ? max(0, target) : 0
    }
    public var remaining: Double { max(0, target - eaten) }
    public var excess: Double { max(0, eaten - target) }
    public var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }
}
