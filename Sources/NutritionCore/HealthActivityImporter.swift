import Foundation

public enum HealthActivityImporter {
    public static func read(url: URL) throws -> [DailyActivity] {
        if url.pathExtension.lowercased() == "xml" {
            guard let parser = XMLParser(contentsOf: url) else { throw PersonalError.invalidFormat }
            return try parseXML(parser)
        }
        guard url.pathExtension.lowercased() == "json",
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 5_000_000 else { throw PersonalError.invalidFormat }
        return try readJSON(Data(contentsOf: url))
    }
    public static func readXML(_ data: Data) throws -> [DailyActivity] { try parseXML(XMLParser(data: data)) }
    private static func parseXML(_ parser: XMLParser) throws -> [DailyActivity] {
        let delegate = HealthXMLDelegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.invalid, delegate.isHealthData, let exportDate = delegate.exportDate else {
            throw PersonalError.invalidActivity
        }
        guard !delegate.totals.isEmpty else { throw PersonalError.noActivity }
        return delegate.totals.map { DailyActivity(day: $0.key, activeCalories: $0.value, updatedAt: exportDate, source: .appleHealth) }
            .sorted { $0.day > $1.day }
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
}

private final class HealthXMLDelegate: NSObject, XMLParserDelegate {
    var totals: [String: Double] = [:]
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
        guard let day = attributes["dateComponents"], DayKey.isValid(day),
              let raw = attributes["activeEnergyBurned"], let amount = Double(raw), amount.isFinite, amount >= 0,
              let unit = attributes["activeEnergyBurnedUnit"], ["kcal", "kJ"].contains(unit) else { fail(parser); return }
        let calories = unit == "kJ" ? amount / 4.184 : amount
        guard calories <= 30_000 else { fail(parser); return }
        if let previous = totals[day], abs(previous - calories) > 0.001 { fail(parser); return }
        totals[day] = calories
    }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
    private func fail(_ parser: XMLParser) { invalid = true; parser.abortParsing() }
}
