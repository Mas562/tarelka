import SwiftUI
import UserNotifications
import NutritionCore

@MainActor
final class ReminderStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var draft = ReminderPlan()
    @Published private(set) var saved = ReminderPlan()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var denied = false
    private let file: URL
    private var storageError: String?
    private let prefix = "tarelka.meal."
    private var center: UNUserNotificationCenter { .current() }
    init(directory: URL) {
        file = directory.appendingPathComponent("reminders.json")
        super.init()
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(contentsOf: file))
                guard plan.isValid else { throw FoodError.invalidResponse }
                draft = plan; saved = plan
            } catch { storageError = "Не удалось прочитать расписание. Существующий файл сохранён."; message = storageError }
        }
    }
    func restore() async {
        guard Bundle.main.bundleIdentifier?.hasPrefix("app.tarelka.") == true else { return }
        center.delegate = self
        guard storageError == nil, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let status = await center.notificationSettings().authorizationStatus
            denied = status == .denied
            if !saved.enabled || status == .authorized || status == .provisional { try await schedule(saved) }
            else if saved.enabled { message = "Для напоминаний разрешите уведомления «Тарелки» в настройках macOS." }
        } catch { message = "Не удалось восстановить напоминания: \(error.localizedDescription)" }
    }
    func save() async {
        guard !busy, draft.isValid else { return }
        guard storageError == nil else { message = storageError; return }
        busy = true; message = nil; defer { busy = false }
        let plan = draft
        do {
            if plan.enabled {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                denied = !granted
                guard granted else { message = "Уведомления выключены в macOS. Разрешите их для «Тарелки» и сохраните расписание ещё раз."; return }
            }
            // Validate and encode before replacing the app's own notifications.
            let bytes = try JSONEncoder().encode(plan)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await schedule(plan)
            do { try bytes.write(to: file, options: .atomic) }
            catch { try? await schedule(saved); throw error }
            saved = plan
            message = plan.enabled ? "Расписание сохранено. macOS будет напоминать каждый день." : "Напоминания выключены."
        } catch { message = "Не удалось сохранить напоминания: \(error.localizedDescription)" }
    }
    private func schedule(_ plan: ReminderPlan) async throws {
        let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        do {
            for meal in plan.meals where plan.enabled && meal.enabled {
                let content = UNMutableNotificationContent()
                content.title = "\(meal.title) скоро"
                if plan.leadMinutes == 0 { content.title = "Время: \(meal.title.lowercased())" }
                content.body = "Не забудь показать, чем сегодня перекусил: сфотографируй еду и запиши её в «Тарелку»."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: meal.notificationTime(leadMinutes: plan.leadMinutes), repeats: true)
                try await center.add(UNNotificationRequest(identifier: prefix + meal.id.uuidString, content: content, trigger: trigger))
            }
            let keep = Set(plan.meals.filter { plan.enabled && $0.enabled }.map { prefix + $0.id.uuidString })
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter { !keep.contains($0) })
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: plan.meals.map { prefix + $0.id.uuidString })
            for request in old { try? await center.add(request) }
            throw error
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: .openMealFromReminder, object: nil) }
    }
}
extension Notification.Name { static let openMealFromReminder = Notification.Name("TarelkaOpenMealFromReminder") }

struct ReminderSettingsView: View {
    @ObservedObject var store: ReminderStore
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Label("Твой распорядок", systemImage: "bell.badge").font(.system(size: 18, weight: .semibold))
                Toggle("Напоминать записать еду", isOn: $store.draft.enabled)
                Text("Укажи обычное время еды. Напоминания приходят на этот Mac каждый день, даже когда окно закрыто. Режим фокусирования и сон Mac могут задержать показ.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                if store.draft.enabled {
                    Picker("Напоминать", selection: $store.draft.leadMinutes) {
                        Text("В момент еды").tag(0); Text("За 15 минут").tag(15); Text("За 30 минут").tag(30); Text("За час").tag(60)
                    }
                    ForEach(store.draft.meals) { meal in
                        HStack {
                            Toggle("Включить \(meal.title)", isOn: mealBinding(meal).enabled).labelsHidden()
                            TextField("Приём пищи", text: mealBinding(meal).title).inputSurface()
                            DatePicker("Время \(meal.title)", selection: timeBinding(meal), displayedComponents: .hourAndMinute).labelsHidden()
                            Text(timeLabel(meal)).font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(width: 120)
                            Button { store.draft.meals.removeAll { $0.id == meal.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).disabled(store.draft.meals.count == 1).accessibilityLabel("Удалить \(meal.title)")
                        }
                    }
                    Button("Добавить приём пищи") { store.draft.meals.append(MealReminder(title: "Перекус", hour: 16)) }
                        .buttonStyle(SoftButton()).disabled(store.draft.meals.count >= 8)
                }
                if let message = store.message { Text(message).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                HStack {
                    Button(store.busy ? "Сохраняю…" : "Сохранить расписание") { Task { await store.save() } }
                        .buttonStyle(SoftButton()).disabled(!store.draft.isValid)
                    if store.denied {
                        Button("Настройки уведомлений macOS") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                        }.buttonStyle(.link)
                    }
                }
            }.disabled(store.busy)
        }
    }
    private func mealBinding(_ meal: MealReminder) -> Binding<MealReminder> {
        Binding(get: { store.draft.meals.first { $0.id == meal.id } ?? meal }, set: { value in
            guard let i = store.draft.meals.firstIndex(where: { $0.id == meal.id }) else { return }
            store.draft.meals[i] = value
        })
    }
    private func timeBinding(_ meal: MealReminder) -> Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: mealBinding(meal).wrappedValue.hour, minute: mealBinding(meal).wrappedValue.minute)) ?? Date() }, set: { date in
            var value = mealBinding(meal).wrappedValue
            value.hour = Calendar.current.component(.hour, from: date); value.minute = Calendar.current.component(.minute, from: date)
            mealBinding(meal).wrappedValue = value
        })
    }
    private func timeLabel(_ meal: MealReminder) -> String {
        let time = meal.notificationTime(leadMinutes: store.draft.leadMinutes)
        return String(format: "Напомню в %02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }
}
