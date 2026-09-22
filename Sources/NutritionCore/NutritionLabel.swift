import Foundation
import Vision

/// A Vision observation in normalized image coordinates (origin at the bottom left).
public struct LabelTextBlock: Sendable {
    public let text: String
    public let rect: CGRect
    public init(_ text: String, rect: CGRect) { self.text = text; self.rect = rect }
}

public struct LabelScan: Sendable {
    public let text: String
    public let unit: PortionUnit?
    public let calories: Double?
    public let protein: Double?
    public let fat: Double?
    public let carbs: Double?
    public var foundCount: Int { [calories, protein, fat, carbs].compactMap { $0 }.count }
}

public enum NutritionLabelParser {
    private static let protein = #"\b(?:белки|белок|белков|proteins?)\b"#
    private static let fat = #"\b(?:жиры|жир|жиров|(?:total\s+)?fat)\b"#
    private static let carbs = #"\b(?:углеводы|углеводов|(?:total\s+)?carbohydrates?|carbs)\b"#
    private static let energy = #"\b(?:энергетическая\s+ценность|калорийность|калории|energy|calories)\b"#
    private static let basis = #"\b100\s*(?:мл|ml|г|гр|g)(?!\p{L})"#

    public static func parse(blocks: [LabelTextBlock]) -> LabelScan {
        // Vision often returns the row label and its numeric column as separate observations.
        // Merge only vertically overlapping rows; multiple columns remain multiple candidates.
        var rows: [[LabelTextBlock]] = []
        for block in blocks.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let index = rows.firstIndex(where: {
                guard let anchor = $0.first else { return false }
                return abs(anchor.rect.midY - block.rect.midY) < min(anchor.rect.height, block.rect.height) * 0.55
            }) { rows[index].append(block) }
            else { rows.append([block]) }
        }
        return parse(text: rows.map { $0.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: "  ") }.joined(separator: "\n"))
    }

    public static func parse(text: String) -> LabelScan {
        let source = text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        // A package's net weight (e.g. “100 г”) is not a nutrition serving basis.
        let bases = source.components(separatedBy: .newlines).flatMap { line in
            matches(basis, line).filter { match in
                let prefix = (line as NSString).substring(to: match.range.location)
                return !matches(#"(?:\bна|\bв|\bper)\s*$"#, prefix).isEmpty
                    || !matches(#"пищевая\s+ценность|nutrition"#, prefix).isEmpty
                    || line.trimmingCharacters(in: .whitespaces) == (line as NSString).substring(with: match.range)
            }.map { (line as NSString).substring(with: $0.range) }
        }
        let units = Set(bases.map { $0.contains("мл") || $0.contains("ml") ? PortionUnit.milliliters : .grams })
        let unit = units.count == 1 ? units.first : nil
        // Values per serving are never silently relabelled as values per 100 g/ml.
        guard unit != nil else { return LabelScan(text: text, unit: nil, calories: nil, protein: nil, fat: nil, carbs: nil) }
        let allFields = [protein, fat, carbs, energy].joined(separator: "|")
        var candidates: [String: [Double]] = [:]
        var ambiguous = Set<String>()
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: basis, with: "", options: .regularExpression)
            let labels = matches(allFields, line)
            for (index, match) in labels.enumerated() {
                let label = (line as NSString).substring(with: match.range)
                let key = !matches(protein, label).isEmpty ? "protein" : !matches(fat, label).isEmpty ? "fat" : !matches(carbs, label).isEmpty ? "carbs" : "calories"
                let prefix = (line as NSString).substring(to: match.range.location)
                if key == "fat", !matches(#"(?:насыщ|транс|saturat|trans)\S*\s*$"#, prefix).isEmpty { continue }
                let start = NSMaxRange(match.range)
                let end = index + 1 < labels.count ? labels[index + 1].range.location : (line as NSString).length
                let tail = (line as NSString).substring(with: NSRange(location: start, length: end - start))
                    .components(separatedBy: try! NSRegularExpression(pattern: #"из них|в том числе|of which|including"#)).first ?? ""
                let values = key == "calories" ? calorieValues(tail, englishCalories: label == "calories") : numericValues(tail)
                if values.count == 1, let value = values.first, value <= (key == "calories" ? 1000 : 100) {
                    candidates[key, default: []].append(value)
                } else if !values.isEmpty { ambiguous.insert(key) }
            }
            // Labels may put kcal on its own row without the word “energy”.
            if labels.isEmpty {
                let values = calorieValues(line, englishCalories: false)
                if values.count == 1, let value = values.first, value <= 1000 { candidates["calories", default: []].append(value) }
                else if !values.isEmpty { ambiguous.insert("calories") }
            }
        }
        func value(_ key: String) -> Double? {
            let unique = Set(candidates[key] ?? [])
            return !ambiguous.contains(key) && unique.count == 1 ? unique.first : nil
        }
        return LabelScan(text: text, unit: unit, calories: value("calories"), protein: value("protein"), fat: value("fat"), carbs: value("carbs"))
    }

    private static func numericValues(_ text: String) -> [Double] {
        // A range or “less than” is not an exact label value. Percent daily values are ignored.
        guard matches(#"[<>≤≥]|менее|более|less|more|\d\s*[-–—]\s*\d|[-−]\s*\d"#, text).isEmpty else { return [] }
        let clean = text.replacingOccurrences(of: #"\d+(?:[.,]\d+)?\s*%"#, with: "", options: .regularExpression)
        return matches(#"\d+(?:[.,]\d+)?"#, clean).compactMap { Numbers.parse((clean as NSString).substring(with: $0.range)) }
    }

    private static func calorieValues(_ text: String, englishCalories: Bool) -> [Double] {
        let number = #"(\d+(?:[.,]\d+)?)"#
        let unit = #"(?:ккал|kcal)\b"#
        let clean = text.replacingOccurrences(of: number + #"\s*(?:кдж|kj)\b"#, with: "", options: .regularExpression)
        let values = numericValues(clean)
        guard !values.isEmpty else { return [] }
        let explicit = !matches(number + #"\s*"# + unit, clean).isEmpty || !matches(unit + #"\s*[:=]?\s*"# + number, clean).isEmpty
        // A second unlabelled numeric column is still ambiguous even if “kcal” appears only once.
        return explicit || englishCalories ? values : []
    }

    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        guard let match = expression.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return [self] }
        return [(self as NSString).substring(to: match.range.location)]
    }
}

public enum NutritionLabelReader {
    public static func read(_ data: Data) async throws -> LabelScan {
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.008
            try VNImageRequestHandler(data: data).perform([request])
            try Task.checkCancellation()
            let blocks = (request.results ?? []).compactMap { observation -> LabelTextBlock? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return LabelTextBlock(candidate.string, rect: observation.boundingBox)
            }
            return NutritionLabelParser.parse(blocks: blocks)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
