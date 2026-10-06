import Foundation

public struct HealthActivityImport: Sendable {
    public let entries: [DailyActivity]
    /// Daily rows that were malformed or contradictory and were left out instead of failing the whole file.
    public let skipped: Int
}

public enum HealthActivityImporter {
    public static func read(url: URL) throws -> [DailyActivity] { try readReport(url: url).entries }
    public static func readReport(url: URL) throws -> HealthActivityImport {
        if url.pathExtension.lowercased() == "xml" {
            // Health exports can be several gigabytes; stream the file instead of loading it into memory.
            guard let stream = InputStream(url: url) else { throw PersonalError.invalidFormat }
            return try parseXML(XMLParser(stream: stream))
        }
        guard url.pathExtension.lowercased() == "json",
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 5_000_000 else { throw PersonalError.invalidFormat }
        return HealthActivityImport(entries: try readJSON(Data(contentsOf: url)), skipped: 0)
    }
    public static func readXML(_ data: Data) throws -> [DailyActivity] { try readXMLReport(data).entries }
    public static func readXMLReport(_ data: Data) throws -> HealthActivityImport { try parseXML(XMLParser(data: data)) }
    private static func parseXML(_ parser: XMLParser) throws -> HealthActivityImport {
        let delegate = HealthXMLDelegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.invalid, delegate.isHealthData, let exportDate = delegate.exportDate else {
            throw PersonalError.invalidActivity
        }
        let valid = delegate.totals.filter { !delegate.conflicting.contains($0.key) }
        guard !valid.isEmpty else {
            throw delegate.skipped > 0 || !delegate.conflicting.isEmpty ? PersonalError.invalidActivity : PersonalError.noActivity
        }
        let entries = valid.map { DailyActivity(day: $0.key, activeCalories: $0.value, updatedAt: exportDate, source: .appleHealth) }
            .sorted { $0.day > $1.day }
        return HealthActivityImport(entries: entries, skipped: delegate.skipped + delegate.conflicting.count)
    }
    /// A transfer file contains daily totals, never additive samples. Reimport replaces a day.
    public static func readJSON(_ data: Data) throws -> [DailyActivity] {
        struct Transfer: Decodable { let version: Int; let days: [Entry] }
        struct Entry: Decodable { let date: String; let active_kcal: Double; let updated_at: String }
        let transfer: Transfer
        do { transfer = try JSONDecoder().decode(Transfer.self, from: data) }
        catch { throw PersonalError.invalidFormat }
        guard transfer.version == 1, !transfer.days.isEmpty else { throw PersonalError.invalidFormat }
        let formatter = ISO8601DateFormatter()
        let results = try transfer.days.map { entry in
            guard let date = formatter.date(from: entry.updated_at) else { throw PersonalError.invalidActivity }
            let item = DailyActivity(day: entry.date, activeCalories: entry.active_kcal, updatedAt: date, source: .transferFile)
            guard item.isValid else { throw PersonalError.invalidActivity }; return item
        }
        guard Set(results.map(\.day)).count == results.count else { throw PersonalError.invalidActivity }
        return results.sorted { $0.day > $1.day }
    }
    /// Health writes "Cal" (a food calorie, equal to 1 kcal) in some locales.
    static func kilocalories(_ amount: Double, unit: String) -> Double? {
        switch unit {
        case "kcal", "Cal": return amount
        case "kJ": return amount / 4.184
        default: return nil
        }
    }
}

private final class HealthXMLDelegate: NSObject, XMLParserDelegate {
    var totals: [String: Double] = [:]
    var conflicting: Set<String> = []
    var skipped = 0
    var exportDate: Date?
    var invalid = false
    var isHealthData = false
    private var depth = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        if depth == 1 { isHealthData = elementName == "HealthData" }
        guard isHealthData, depth == 2 else { return }
        if elementName == "ExportDate" {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; formatter.isLenient = false
            exportDate = attributes["value"].flatMap { formatter.date(from: $0) }
            if exportDate == nil { fail(parser) }
        }
        // Records and Workouts overlap. Apple's activity summary is the single daily Move total.
        guard elementName == "ActivitySummary" else { return }
        // One bad or contradictory day is left out; it must not discard every other day of the export.
        guard let day = attributes["dateComponents"], DayKey.isValid(day),
              let raw = attributes["activeEnergyBurned"], let amount = Double(raw), amount.isFinite, amount >= 0,
              let unit = attributes["activeEnergyBurnedUnit"],
              let calories = HealthActivityImporter.kilocalories(amount, unit: unit), calories <= 30_000 else { skipped += 1; return }
        if let previous = totals[day], abs(previous - calories) > 0.001 { conflicting.insert(day); return }
        totals[day] = calories
    }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
    private func fail(_ parser: XMLParser) { invalid = true; parser.abortParsing() }
}
