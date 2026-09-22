import AppKit
import SwiftUI
import NutritionCore

@MainActor
final class LocalSetupModel: ObservableObject {
    let role: OllamaService.ModelRole
    init(role: OllamaService.ModelRole = .vision) { self.role = role }
    @Published var isReady = false
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var progress: Double?
    @Published var status = "Проверим, готов ли Mac к распознаванию."
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    func check() {
        guard !isChecking, !isDownloading else { return }
        isChecking = true
        let token = UUID(); operationID = token
        task = Task { [self] in
            do {
                try await OllamaService().checkReady(role: role)
                guard !Task.isCancelled, token == operationID else { return }
                isReady = true; status = "\(role.displayName) готова к работе без интернета и оплаты."
            } catch {
                guard !Task.isCancelled, token == operationID else { return }
                isReady = false
                status = (error as? LocalModelError)?.localizedDescription ?? LocalModelError.unavailable.localizedDescription
            }
            isChecking = false; task = nil
        }
    }
    func download() {
        guard !isDownloading, !isChecking else { return }
        isDownloading = true; isReady = false; progress = nil
        status = "Подключаемся к Ollama. Для загрузки нужен интернет…"
        let token = UUID(); operationID = token
        task = Task { [self] in
            do {
                try await OllamaService().downloadModel(role: role) { [weak self] event in
                    await self?.update(event, token: token)
                }
                guard !Task.isCancelled, token == operationID else { return }
                isReady = true; status = "Модель скачана. Всё готово к работе без интернета и оплаты."
            } catch {
                guard !Task.isCancelled, token == operationID else { return }
                if let error = error as? URLError, error.code == .cannotConnectToHost {
                    status = LocalModelError.unavailable.localizedDescription
                } else { status = (error as? LocalModelError)?.localizedDescription ?? LocalModelError.downloadFailed.localizedDescription }
            }
            isDownloading = false; task = nil; progress = nil
        }
    }
    private func update(_ event: OllamaService.DownloadProgress, token: UUID) {
        guard token == operationID else { return }
        progress = event.fraction
        if let fraction = progress { status = "Загружается файл модели: \(Int(fraction * 100))%" }
        else { status = "Подготавливаем модель. Первое скачивание может занять несколько минут…" }
    }
    func cancelDownload() {
        operationID = UUID(); task?.cancel(); task = nil
        isDownloading = false; isChecking = false; progress = nil
        status = "Загрузка остановлена. Её можно продолжить той же кнопкой."
    }
    func openOllama() {
        let folders = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        guard let url = folders.map({ $0.appendingPathComponent("Ollama.app") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            status = "Сначала скачайте Ollama по ссылке ниже и перенесите в папку «Программы»."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if error != nil { self.status = "Не удалось открыть Ollama. Откройте её из папки «Программы»." }
                else { self.status = "Ollama открыта. Нажмите «Проверить готовность» или скачайте модель." }
            }
        }
    }
}

struct LocalSettingsView: View {
    @ObservedObject var setup: LocalSetupModel
    private var role: OllamaService.ModelRole { setup.role }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").font(.system(size: 24)).foregroundStyle(Palette.green)
                        .frame(width: 48, height: 48).background(Palette.mint).clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(role == .vision ? "Распознавание на вашем Mac" : "Помощник без лишней нагрузки").font(.system(size: 17, weight: .semibold))
                        Text(role == .vision ? "Без подписки, ключей API и оплаты за фото" : "Лёгкая модель · щадящий режим · бесплатно").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }
                Text(role == .vision ? "Ollama запускает \(role.displayName) прямо на компьютере. После первой загрузки интернет для распознавания не нужен. Фото и уточнения остаются на Mac." : "Для советов используется отдельная \(role.displayName). Она работает на процессоре с ограниченной нагрузкой. Тяжёлая модель для фото при этом не запускается.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Установите бесплатную Ollama и откройте её.")
                    Text("2. Скачайте модель кнопкой ниже — около \(role.downloadSize) один раз.")
                    Text(role == .vision ? "3. Вернитесь к блюду, добавьте фото и вес." : "3. Откройте помощника и задайте вопрос.")
                }.font(.system(size: 12))
                HStack(spacing: 18) {
                    Link("Скачать Ollama ↗", destination: URL(string: "https://ollama.com/download/mac")!)
                    Button("Открыть Ollama") { setup.openOllama() }.buttonStyle(.plain)
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
                HStack(alignment: .top, spacing: 10) {
                    if setup.isChecking { ProgressView().controlSize(.small) }
                    else { Image(systemName: setup.isReady ? "checkmark.circle.fill" : "info.circle") }
                    Text(setup.status).fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 12)).foregroundStyle(Palette.green)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.mint.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 12))
                if setup.isDownloading {
                    if let progress = setup.progress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.small) }
                    Button("Остановить загрузку") { setup.cancelDownload() }.buttonStyle(SoftButton())
                } else {
                    HStack(spacing: 12) {
                        Button(setup.isReady ? "Модель установлена" : "Скачать модель · \(role.downloadSize)") { setup.download() }
                            .buttonStyle(PrimaryButton()).frame(width: 265).disabled(setup.isReady || setup.isChecking)
                        Button("Проверить готовность") { setup.check() }.buttonStyle(SoftButton()).disabled(setup.isChecking)
                    }
                }
                Text(role == .vision ? "Рекомендуется Mac с 16 ГБ памяти или больше. Распознавание может занять несколько минут. Оценку состава и калорий стоит проверить; известные ингредиенты и масло лучше указать в уточнениях." : "Ответ может занять несколько минут. Изменение дневника и активности не запускает помощника автоматически. После ответа модель освобождает память.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(3)
            }
        }.onAppear { setup.check() }
    }
}
