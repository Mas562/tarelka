import SwiftUI
import UniformTypeIdentifiers
import NutritionCore

@MainActor
final class RecipeStore: ObservableObject {
    @Published var foods = ""
    @Published var preferences = ""
    @Published var servings = 1
    @Published private(set) var recipes: [PantryRecipe] = []
    @Published private(set) var uncertainties: [String] = []
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var usedFoods = ""
    @Published private(set) var usedPreferences = ""
    @Published private(set) var usedServings = 1
    @Published private(set) var usedDietaryNotes = ""
    private var task: Task<Void, Never>?
    private var token = UUID()
    func recognize(_ jpeg: Data) {
        cancel(); busy = true; status = "Рассматриваю продукты…"; error = nil
        let id = token
        task = Task {
            do {
                let inventory = try await OllamaService().pantry(jpeg: jpeg)
                guard id == token, !Task.isCancelled else { return }
                uncertainties = inventory.uncertainties
                if inventory.items.isEmpty { error = "Не получилось увидеть продукты. Попробуй другой снимок или перечисли их текстом." }
                else {
                    let addition = inventory.items.joined(separator: ", ")
                    foods = String((foods.isEmpty ? addition : foods + "\n" + addition).prefix(4000))
                    status = "Проверь названия и добавь количества, если знаешь их."
                }
            } catch { if id == token && !Task.isCancelled { self.error = error.localizedDescription } }
            if id == token { busy = false }
        }
    }
    func generate(dietaryNotes: String) {
        cancel(); busy = true; status = "Подбираю рецепты из твоих продуктов…"; error = nil
        let id = token, snapshot = foods
        let preferenceSnapshot = preferences
        let preferences = String((dietaryNotes + "\n" + preferences).prefix(2000)), servings = servings
        task = Task {
            do {
                let result = try await OllamaService().recipes(foods: snapshot, preferences: preferences, servings: servings)
                guard id == token, !Task.isCancelled else { return }
                recipes = result.recipes; usedFoods = snapshot; status = "Рецепты готовы"
                usedPreferences = preferenceSnapshot; usedServings = servings; usedDietaryNotes = dietaryNotes
            } catch { if id == token && !Task.isCancelled { self.error = error.localizedDescription } }
            if id == token { busy = false }
        }
    }
    func cancel() { token = UUID(); task?.cancel(); task = nil; busy = false }
}

struct RecipeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @ObservedObject var store: RecipeStore
    @StateObject private var photo = DrinkPhotoStore()
    @StateObject private var speech = SpeechInput()
    @State private var beforeDictation = ""
    @State private var showingDictation = false
    @State private var panel: NSOpenPanel?
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Из того, что есть дома")
                Text("Что приготовить?").font(.system(size: 35, weight: .semibold)).tracking(-1)
                Text("Покажи продукты, перечисли их или надиктуй. Вместе найдём идею для следующего блюда.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            if let preview = photo.preview {
                                Image(nsImage: preview).resizable().scaledToFill().frame(width: 100, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            } else {
                                Image(systemName: "carrot").font(.system(size: 32)).foregroundStyle(Palette.green)
                                    .frame(width: 80, height: 80).liquidSurface(radius: 22)
                            }
                            VStack(alignment: .leading, spacing: 9) {
                                Button(photo.preview == nil ? "Добавить фото продуктов" : "Заменить фото") { choosePhoto() }.buttonStyle(SoftButton()).disabled(store.busy || photo.busy || speech.recording)
                                if let data = photo.data {
                                    HStack {
                                        Button("Распознать продукты") { model.coach.cancel(); store.recognize(data) }.buttonStyle(.link).disabled(store.busy || speech.recording)
                                        Button("Убрать фото") { photo.remove() }.buttonStyle(.link).disabled(store.busy)
                                    }
                                }
                                Text("Можно по очереди добавить несколько фото. Списки объединятся.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if photo.busy { ProgressView() }
                        }
                        FieldLabel(title: "Продукты дома")
                        TextField("Например: 2 яйца, помидор, 100 г сыра, вчерашний рис", text: $store.foods, axis: .vertical)
                            .lineLimit(3...8).inputSurface().disabled(store.busy || speech.recording || speech.requesting)
                            .onChange(of: store.foods) { _, value in if value.count > 4000 { store.foods = String(value.prefix(4000)) } }
                        Button { speech.reset(); showingDictation = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform").font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Palette.green).frame(width: 42, height: 42)
                                    .background(Palette.mint.opacity(0.6), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Продиктовать продукты").font(.system(size: 13, weight: .semibold))
                                    Text("Говори спокойно, с паузами — я сохраню список").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                            }.padding(12).contentShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).liquidSurface(radius: 18).disabled(store.busy || photo.busy)
                        ForEach(Array(store.uncertainties.enumerated()), id: \.offset) { _, text in Text(text).font(.system(size: 12)).foregroundStyle(Palette.orange) }
                        TextField("Пожелания: без молока, быстро, только сковорода…", text: $store.preferences, axis: .vertical)
                            .lineLimit(1...3).inputSurface().disabled(store.busy)
                            .onChange(of: store.preferences) { _, value in if value.count > 1000 { store.preferences = String(value.prefix(1000)) } }
                        Stepper("Порций: \(store.servings)", value: $store.servings, in: 1...8).disabled(store.busy)
                        Text("Учту также исключения из настроек помощника. Фото не определяет свежесть еды; неизвестные количества нужно уточнить.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        if let error = store.error ?? photo.error ?? speech.error { Text(error).font(.system(size: 12)).foregroundStyle(Palette.orange) }
                        if store.busy {
                            HStack { ProgressView().controlSize(.small); Text(store.status).font(.system(size: 12)); Spacer(); Button("Отменить") { store.cancel() }.buttonStyle(SoftButton()) }
                        } else {
                            Button("Предложить рецепты · бесплатно") {
                                model.coach.cancel(); copied = false
                                store.generate(dietaryNotes: personal.data.dietaryNotes ?? "")
                            }.buttonStyle(PrimaryButton()).disabled(store.foods.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.recording || speech.requesting || photo.busy || model.isAnalyzing)
                        }
                    }
                }
                if !store.recipes.isEmpty {
                    HStack {
                        Text("Идеи для тебя").font(.system(size: 24, weight: .semibold))
                        Spacer()
                        Button(copied ? "Скопировано" : "Скопировать рецепты") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.recipes.map(recipeText).joined(separator: "\n\n"), forType: .string); copied = true
                        }.buttonStyle(SoftButton())
                    }
                    if store.usedFoods != store.foods || store.usedPreferences != store.preferences || store.usedServings != store.servings || store.usedDietaryNotes != (personal.data.dietaryNotes ?? "") {
                        Text("Ниже рецепты для предыдущего списка и пожеланий. Нажми «Предложить рецепты», чтобы обновить их.").font(.system(size: 12)).foregroundStyle(Palette.orange)
                    }
                    ForEach(Array(store.recipes.enumerated()), id: \.offset) { _, recipe in recipeCard(recipe) }
                    Text("Это идеи, а не записи в дневнике. После приготовления взвесь свою порцию и добавь блюдо — КБЖУ рецепта здесь не выдумываются.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }.padding(30).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingDictation) {
            VoiceDictationView(speech: speech, foods: store.foods, onStart: {
                beforeDictation = store.foods
                speech.start()
            }, onDone: {
                speech.stop(); saveDictation(); showingDictation = false
            })
        }
        .onChange(of: speech.transcript) { _, _ in saveDictation() }
        .onDisappear { speech.stop(); photo.cancel(); store.cancel(); panel?.cancel(nil); panel = nil }
    }
    private func saveDictation() {
        guard !speech.transcript.isEmpty else { return }
        store.foods = String((beforeDictation.isEmpty ? speech.transcript : beforeDictation + "\n" + speech.transcript).prefix(4000))
    }
    private func choosePhoto() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
        picker.canChooseFiles = true; picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.prompt = "Добавить фото"; panel = picker
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                picker.beginSheetModal(for: window) { response in
                    if response == .OK, let url = picker.url { photo.load(url) }
                    panel = nil
                }
            } else { picker.begin { response in if response == .OK, let url = picker.url { photo.load(url) }; panel = nil } }
        }
    }
    private func recipeCard(_ recipe: PantryRecipe) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(recipe.title).font(.system(size: 22, weight: .semibold))
                Label("\(recipe.minutes) мин · порций: \(recipe.servings)", systemImage: "clock").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text("Ингредиенты").fontWeight(.semibold)
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, item in Text("• " + item).font(.system(size: 13)) }
                if !recipe.missing.isEmpty {
                    Text("Нужно докупить: " + recipe.missing.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Palette.orange)
                }
                Divider()
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.green).frame(width: 24, height: 24).background(Palette.mint, in: Circle())
                        Text(step).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !recipe.note.isEmpty { Text(recipe.note).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
            }.textSelection(.enabled)
        }
    }
    private func recipeText(_ recipe: PantryRecipe) -> String {
        "\(recipe.title)\n\(recipe.minutes) мин · порций: \(recipe.servings)\n\n" + recipe.ingredients.joined(separator: "\n") + "\n\n" + recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + (recipe.missing.isEmpty ? "" : "\nДокупить: " + recipe.missing.joined(separator: ", ")) + "\n" + recipe.note
    }
}
