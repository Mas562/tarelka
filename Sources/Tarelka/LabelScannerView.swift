import SwiftUI
import UniformTypeIdentifiers
import NutritionCore

struct LabelScannerView: View {
    @State private var filePanel: NSOpenPanel?
    @State private var job: PhotoJob?
    @State private var preview: NSImage?
    @State private var scan: LabelScan?
    @State private var busy = false
    @State private var error: String?
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var unit: PortionUnit
    @State private var confirmed = false
    let onCancel: () -> Void
    let onApply: (Nutrients, PortionUnit) -> Void

    private struct PhotoJob: Identifiable { let id = UUID(); let url: URL }
    init(unit: PortionUnit, onCancel: @escaping () -> Void, onApply: @escaping (Nutrients, PortionUnit) -> Void) {
        _unit = State(initialValue: unit); self.onCancel = onCancel; self.onApply = onApply
    }
    private var nutrients: Nutrients? {
        guard let kcal = Numbers.parse(calories), let p = Numbers.parse(protein),
              let f = Numbers.parse(fat), let c = Numbers.parse(carbs) else { return nil }
        let result = Nutrients(calories: kcal, protein: p, fat: f, carbs: c)
        return result.isValidPer100 ? result : nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder").font(.system(size: 26)).foregroundStyle(Palette.green)
                    .frame(width: 54, height: 54).background(Palette.mint, in: RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 5) {
                    Text("БЖУ с упаковки").font(.system(size: 25, weight: .semibold))
                    Text("Фото → проверка → ваш продукт").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Label("На этом Mac", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Palette.green)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Palette.surface.opacity(0.75))
                            if let preview {
                                Image(nsImage: preview).resizable().scaledToFit().padding(10)
                                    .accessibilityLabel("Фотография упаковки для проверки")
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.macro").font(.system(size: 39, weight: .light))
                                    Text("Снимите таблицу\nпищевой ценности крупно").multilineTextAlignment(.center).font(.system(size: 13))
                                }.foregroundStyle(Palette.secondary)
                            }
                        }.frame(height: 270)
                        Button { choosePhoto() } label: {
                            Label(preview == nil ? "Выбрать фото упаковки" : "Выбрать другое фото", systemImage: "photo.on.rectangle")
                        }.buttonStyle(SoftButton()).disabled(busy)
                        Text("В кадре должны быть БЖУ, калории и строка «на 100 г» или «на 100 мл». Для таблицы с несколькими колонками оставьте в кадре названия и колонку на 100.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        if let scan, !scan.text.isEmpty {
                            DisclosureGroup("Прочитанный текст") {
                                Text(scan.text).font(.system(size: 11)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
                            }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }.frame(width: 280)
                    VStack(alignment: .leading, spacing: 14) {
                        if busy {
                            HStack { ProgressView().controlSize(.small); Text("Читаю упаковку…").font(.system(size: 12)) }
                        } else if let scan {
                            Label("Найдено значений: \(scan.foundCount) из 4", systemImage: scan.foundCount == 4 ? "checkmark.viewfinder" : "text.magnifyingglass")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.green)
                            Text(scan.unit == nil ? "Не удалось определить данные на 100 г или 100 мл. Выберите другой снимок или впишите пересчитанные значения вручную." : "Сверьте цифры с фото. Пустые поля нужно заполнить: неясные значения не подставляются автоматически.")
                                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Здесь появятся значения с фото").font(.system(size: 14, weight: .medium))
                            Text("Бесплатно, без интернета и без запуска нейросети для блюд.")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                        Picker("Значения на упаковке", selection: $unit) {
                            Text("На 100 г").tag(PortionUnit.grams)
                            Text("На 100 мл").tag(PortionUnit.milliliters)
                        }.pickerStyle(.segmented)
                        labeledField("Калории, ккал", text: $calories)
                        HStack(spacing: 12) {
                            labeledField("Белки, г", text: $protein)
                            labeledField("Жиры, г", text: $fat)
                        }
                        labeledField("Углеводы, г", text: $carbs)
                        Toggle("Я сверил(а) значения: они указаны на \(unit.basis)", isOn: $confirmed)
                            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        if scan != nil, nutrients == nil, !busy {
                            Text("Нужны четыре корректных числа. Если на упаковке указан ноль, впишите 0.")
                                .font(.system(size: 11)).foregroundStyle(Palette.orange)
                        }
                        if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.orange) }
                    }.frame(maxWidth: .infinity).disabled(busy)
                }
            }
            HStack {
                Text("Фото упаковки не отправляется в интернет.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Отмена", action: onCancel).buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button("Перенести в продукт") {
                    if let nutrients { onApply(nutrients, unit) }
                }.buttonStyle(PrimaryButton()).disabled(busy || !confirmed || nutrients == nil)
            }
        }.padding(26).frame(width: 770, height: 650).background(Palette.background)
            .onChange(of: unit) { _, _ in confirmed = false }
            .onDisappear { filePanel?.cancel(nil); filePanel = nil }
            .task(id: job?.id) {
                guard let job else { return }
                busy = true; error = nil; scan = nil; confirmed = false
                calories = ""; protein = ""; fat = ""; carbs = ""; preview = nil
                do {
                    let data = try await Task.detached(priority: .userInitiated) { try PhotoLoader.load(url: job.url, maxPixelSize: 2800) }.value
                    try Task.checkCancellation()
                    preview = NSImage(data: data)
                    let result = try await NutritionLabelReader.read(data)
                    try Task.checkCancellation()
                    scan = result
                    if let detected = result.unit { unit = detected }
                    calories = result.calories.map(Numbers.input) ?? ""
                    protein = result.protein.map(Numbers.input) ?? ""
                    fat = result.fat.map(Numbers.input) ?? ""
                    carbs = result.carbs.map(Numbers.input) ?? ""
                    if result.text.isEmpty { error = "Текст не найден. Попробуйте снять упаковку ближе, без бликов." }
                } catch is CancellationError { return }
                catch { self.error = "Не удалось прочитать упаковку. \(error.localizedDescription)" }
                busy = false
            }
    }

    private func choosePhoto() {
        guard filePanel == nil else { return }
        let panel = NSOpenPanel()
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.message = "Выберите крупный снимок таблицы пищевой ценности"
        panel.prompt = "Прочитать упаковку"
        filePanel = panel
        // Present after the current SwiftUI update, without a nested modal event loop.
        DispatchQueue.main.async {
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                Task { @MainActor in
                    filePanel = nil
                    if response == .OK, let url = panel.url { job = PhotoJob(url: url) }
                }
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
        }
    }
}
