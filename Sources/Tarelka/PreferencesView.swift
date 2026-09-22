import SwiftUI
import NutritionCore

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = AppearanceChoice.light.rawValue
    @State private var key = ""
    @State private var visionModel = OpenAIService.defaultModel
    @State private var saved = false
    @State private var showAdvanced = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Тарелка")
                    Text("Настройки").font(.system(size: 31, weight: .semibold)).tracking(-0.9)
                    Text("Подключите распознавание блюд по фото.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Оформление", systemImage: "circle.lefthalf.filled").font(.system(size: 18, weight: .semibold))
                        Picker("Тема приложения", selection: $appearance) {
                            ForEach(AppearanceChoice.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }.pickerStyle(.segmented)
                        Text("Стеклянные панели подстраиваются под выбранную тему.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                ReminderSettingsView(store: model.reminders)
                CatalogSettingsView()
                Picker("Способ распознавания", selection: $model.provider) {
                    ForEach(RecognitionProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }.pickerStyle(.segmented).disabled(model.isAnalyzing || model.localSetup.isDownloading)
                if model.provider == .local {
                    LocalSettingsView(setup: model.localSetup)
                    LocalSettingsView(setup: model.coachSetup)
                } else {
                Card {
                    VStack(alignment: .leading, spacing: 19) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Palette.green)
                                .frame(width: 48, height: 48).background(Palette.mint).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Распознавание с OpenAI").font(.system(size: 17, weight: .semibold))
                                Text(model.hasKey ? "Ключ сохранён на этом Mac" : "Нужен ваш ключ API")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if model.hasKey { Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.green) }
                        }
                        Text("Фото, вес и уточнения отправляются в OpenAI только по кнопке «Рассчитать по фото». Запросы оплачиваются по тарифам API OpenAI.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 9) {
                            FieldLabel(title: model.hasKey ? "Новый ключ API (если хотите заменить)" : "Ключ API")
                            SecureField(model.hasKey ? "Ключ уже сохранён" : "sk-…", text: $key).inputSurface().accessibilityLabel("Ключ OpenAI API")
                                .onChange(of: key) { _, _ in saved = false }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                            Text("Хранится в Связке ключей macOS, отдельно от дневника.")
                        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        DisclosureGroup("Дополнительно", isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldLabel(title: "Модель с поддержкой фото и структурированных ответов")
                                TextField(OpenAIService.defaultModel, text: $visionModel).inputSurface()
                                Text("По умолчанию: \(OpenAIService.defaultModel). Доступ зависит от вашего аккаунта OpenAI.")
                                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }.padding(.top, 10)
                        }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        HStack(spacing: 15) {
                            Button(saved ? "Сохранено" : "Сохранить настройки") {
                                if model.saveSettings(key: key, model: visionModel) { key = ""; saved = true }
                            }.buttonStyle(PrimaryButton()).frame(width: 230)
                                .disabled(visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAnalyzing)
                            if model.hasKey {
                                Button("Удалить ключ") { model.deleteKey(); key = ""; saved = false }
                                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary).disabled(model.isAnalyzing)
                            }
                        }
                        HStack(spacing: 20) {
                            Link("Создать ключ ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            Link("Тарифы API ↗", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                        }.font(.system(size: 11)).foregroundStyle(Palette.green)
                    }
                }
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Ваш дневник остаётся на Mac", systemImage: "internaldrive").font(.system(size: 15, weight: .medium))
                        Text("Записи и уменьшенные копии фото сохраняются локально. Перед отправкой фото очищается от исходных метаданных, включая геолокацию.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                        Button("Показать папку дневника") {
                            do {
                                try FileManager.default.createDirectory(at: model.repository.directory, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(model.repository.directory)
                            } catch { model.errorMessage = error.localizedDescription }
                        }.buttonStyle(SoftButton())
                    }
                }
                HStack {
                    Text("Тарелка 2.3 · Сделано для спокойного учёта еды").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Вернуться к блюду") { model.screen = .newMeal }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
                }
            }.padding(.horizontal, 32).padding(.top, 23).padding(.bottom, 36).frame(maxWidth: 880).frame(maxWidth: .infinity)
        }.onAppear { visionModel = model.modelName }
            .onDisappear { key = "" }
    }
}
