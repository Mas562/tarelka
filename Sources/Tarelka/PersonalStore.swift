import AppKit
import SwiftUI
import NutritionCore
import UniformTypeIdentifiers

@MainActor
final class PersonalStore: ObservableObject {
    @Published private(set) var data = PersonalData()
    @Published var error: String?
    @Published var status: String?
    @Published private(set) var storageError: String?
    @Published private(set) var importing = false
    private let repository: PersonalRepository
    private var lastFileModification: Date?
    private var filePanel: NSOpenPanel?
    init(directory: URL) {
        repository = PersonalRepository(directory: directory)
        do {
            let backup = try? repository.recoverDamaged()
            data = try repository.load()
            if let backup {
                error = "Часть продуктов или настроек была повреждена и пропущена. Исходный файл сохранён как \(backup.lastPathComponent) в папке дневника."
            }
        } catch { storageError = "Не удалось открыть продукты и профиль. Файл сохранён без изменений: \(error.localizedDescription)" }
    }
    @discardableResult
    private func commit(_ value: PersonalData) -> Bool {
        guard storageError == nil else { return false }
        do { data = try repository.save(value, replacing: data); error = nil; return true }
        catch {
            self.error = error.localizedDescription
            // Show what the other copy saved so the user repeats the action on current data.
            let conflict = (error as? PersonalError) == .storageConflict
            if conflict, let fresh = try? repository.load() { data = fresh }
            return false
        }
    }
    func saveProduct(_ product: SavedProduct) -> Bool {
        var updated = data
        updated.products.removeAll { $0.id == product.id }; updated.products.append(product)
        updated.products.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return commit(updated)
    }
    func deleteProduct(_ product: SavedProduct) {
        var updated = data; updated.products.removeAll { $0.id == product.id }; _ = commit(updated)
    }
    func saveProfile(_ profile: CalorieProfile?, target: Double?, settings: BudgetSettings? = nil) -> Bool {
        var updated = data; updated.profile = profile; updated.manualTarget = target
        if let settings { updated.budgetSettings = settings }
        return commit(updated)
    }
    func saveCoachPreferences(enabled: Bool, notes: String) -> Bool {
        var updated = data; updated.coachEnabled = enabled; updated.dietaryNotes = String(notes.prefix(1000))
        return commit(updated)
    }
    func activity(on date: Date) -> DailyActivity? {
        let day = DayKey.string(date)
        return data.activity.first { $0.day == day }
    }
    func saveManualActivity(calories: Double, date: Date) -> Bool {
        var updated = data
        do {
            // An explicit correction takes precedence even after an import from a device
            // whose clock was ahead. Automatic imports still use timestamp ordering.
            try updated.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: calories, updatedAt: Date(), source: .manual)], preferIncoming: true)
            return commit(updated)
        } catch { self.error = error.localizedDescription; return false }
    }
    func chooseActivityFile(link: Bool) {
        guard !importing, filePanel == nil else { return }
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml, .json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = link ? "Выберите файл активности. Пока приложение открыто, изменения проверяются раз в минуту." : "Распакуйте экспорт «Здоровья» и выберите export.xml."
        panel.prompt = link ? "Подключить файл" : "Импортировать"
        filePanel = panel
        // Present on the next event loop to avoid nesting a modal loop inside a SwiftUI/AX update.
        DispatchQueue.main.async { [weak self] in
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                Task { @MainActor in
                    self?.filePanel = nil
                    if response == .OK, let url = panel.url { self?.importActivity(url, link: link) }
                }
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
        }
    }
    private func importActivity(_ url: URL, link: Bool, silent: Bool = false) {
        guard !importing, storageError == nil else { return }
        importing = true; if !silent { error = nil; status = nil }
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; importing = false }
            do {
                let modification = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let entries = try await Task.detached(priority: .utility) { try HealthActivityImporter.read(url: url) }.value
                var updated = data
                try updated.mergeActivity(entries)
                if link {
                    updated.linkedFileBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    updated.linkedFileName = url.lastPathComponent
                }
                if commit(updated) {
                    if link || silent { lastFileModification = modification }
                    if !silent { status = "Данные активности обработаны: \(entries.count) дн. Повторные даты обновляются, а не складываются." }
                }
            } catch { self.error = "Не удалось прочитать активность: \(error.localizedDescription)" }
        }
    }
    func refreshLinkedFile(force: Bool = false) {
        guard !importing, let bookmark = data.linkedFileBookmark else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let modification = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if force || stale || lastFileModification == nil || modification != lastFileModification { importActivity(url, link: stale, silent: true) }
        } catch { self.error = "Подключённый файл недоступен. Проверьте его загрузку на Mac или подключите заново." }
    }
    func unlinkActivityFile() {
        var updated = data; updated.linkedFileBookmark = nil; updated.linkedFileName = nil
        if commit(updated) { lastFileModification = nil; status = "Файл отключён. Уже полученные итоги сохранены." }
    }
}
