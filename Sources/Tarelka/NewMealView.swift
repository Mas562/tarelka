import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NutritionCore

struct NewMealView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTargeted = false
    @State private var confirmReset = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header.arrive()
                    steps.arrive(delay: 0.06)
                    HStack(alignment: .top, spacing: 22) {
                        photoCard.frame(maxWidth: .infinity).arrive(delay: 0.12)
                        inputCard.frame(maxWidth: .infinity).arrive(delay: 0.2)
                    }
                    if model.hasResult { resultCard.id("result") }
                    else { footnote }
                }.padding(.horizontal, 32).padding(.top, 23).padding(.bottom, 36)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
            }.onChange(of: model.hasResult) { _, hasResult in
                if hasResult { withAnimation(reduceMotion ? nil : .spring(duration: 0.6)) { proxy.scrollTo("result", anchor: .top) } }
            }
        }
        .onAppear { model.beginNewMeal() }
        .confirmationDialog("Очистить текущее блюдо?", isPresented: $confirmReset) {
            Button("Очистить блюдо", role: .destructive) { model.resetDraft() }
            Button("Продолжить заполнение", role: .cancel) {}
        } message: { Text("Несохранённые фото и изменения будут удалены из формы.") }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 11) {
                Eyebrow(text: model.editingID == nil ? "Фото и вес порции" : "Запись в дневнике")
                Text(model.editingID == nil ? "Новое блюдо" : "Уточним это блюдо")
                    .font(.system(size: 32, weight: .semibold)).tracking(-0.9)
                Text("Добавь фото и вес — получи оценку калорий и БЖУ.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if model.hasDraft {
                Button { confirmReset = true } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 15)) }
                    .buttonStyle(SoftButton()).help("Очистить форму").accessibilityLabel("Очистить форму")
            }
        }
    }
    private var steps: some View {
        HStack(spacing: 12) {
            step(1, "Фото блюда", complete: model.photoData != nil)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.line)
            step(2, "Вес порции", complete: model.parsedWeight != nil)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.line)
            step(3, "Калории и БЖУ", complete: model.hasResult)
            Spacer(minLength: 0)
        }.padding(13).liquidSurface(radius: 18, tint: Palette.mint.opacity(0.08))
    }
    private func step(_ number: Int, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(complete ? Palette.green : Palette.mint).frame(width: 25, height: 25)
                if complete { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white) }
                else { Text("\(number)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.green) }
            }
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
        }
    }
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                if let image = model.photoPreview {
                    GeometryReader { geometry in
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                    VStack {
                        HStack {
                            Label("Фото добавлено", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .medium)).padding(9)
                                .background(.regularMaterial).clipShape(Capsule())
                            Spacer()
                            Button { model.removePhoto() } label: { Image(systemName: "xmark").padding(9) }
                                .buttonStyle(.plain).background(.regularMaterial).clipShape(Circle())
                                .accessibilityLabel("Убрать фото").disabled(model.isAnalyzing)
                        }
                        Spacer()
                        Button("Заменить фото") { model.choosePhoto() }.buttonStyle(SoftButton()).disabled(model.isAnalyzing)
                    }.padding(14)
                } else {
                    RoundedRectangle(cornerRadius: 27).fill(LinearGradient(colors: [Palette.mint.opacity(dropTargeted ? 0.9 : 0.5), Palette.surface.opacity(0.8), Palette.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.green.opacity(0.27), style: StrokeStyle(lineWidth: 1.3, dash: [6, 5]))
                    VStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle().fill(Palette.surface.opacity(0.3)).frame(width: 104, height: 104)
                            Circle().stroke(Palette.green.opacity(0.14), lineWidth: 1).frame(width: 76, height: 76).padding(14)
                            Image(systemName: "fork.knife").font(.system(size: 35, weight: .regular)).foregroundStyle(Palette.green)
                                .frame(width: 104, height: 104)
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Palette.green).clipShape(Circle())
                                .overlay(Circle().stroke(Palette.edge, lineWidth: 3)).offset(x: 1, y: -3)
                        }
                        // Keep both symbols in the glass foreground, not behind a sibling glass surface.
                        .liquidSurface(radius: 52, tint: Palette.mint.opacity(0.2))
                        .padding(.bottom, 2)
                        Text("Сначала — фото").font(.system(size: 20, weight: .medium)).tracking(-0.4)
                        Text("Перетащите снимок блюда сюда\nили выберите его на Mac")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
                        Button("Выбрать фото") { model.choosePhoto() }.buttonStyle(SoftButton())
                        Text("JPEG, PNG, HEIC · до 40 МБ").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                    }.padding(25)
                }
            }.frame(height: 338).clipShape(RoundedRectangle(cornerRadius: 27))
                .animation(reduceMotion ? nil : .spring(duration: 0.4), value: dropTargeted)
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                    guard !model.isAnalyzing, let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, url.isFileURL else { return }
                        Task { @MainActor in model.importPhoto(url) }
                    }
                    return true
                }
            HStack {
                Label("Снимайте сверху при хорошем свете", systemImage: "sun.max")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Button { model.pastePhoto() } label: { Image(systemName: "document.on.clipboard") }
                    .buttonStyle(.plain).foregroundStyle(Palette.green).disabled(model.isAnalyzing)
                    .help("Вставить фото · ⌘⇧V").accessibilityLabel("Вставить фото")
            }.padding(.horizontal, 3)
        }
    }
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 7) {
                Image(systemName: "scalemass").foregroundStyle(Palette.green)
                Text("Сколько весит порция?").font(.system(size: 16, weight: .medium))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if model.hasResult && model.weightMode == .ingredients {
                    Text(model.parsedWeight.map { Numbers.display($0) } ?? "—")
                        .font(.system(size: 30, weight: .medium, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Сумма весов ингредиентов")
                } else {
                    TextField("Например, 350", text: $model.weight)
                        .font(.system(size: 30, weight: .medium, design: .rounded)).textFieldStyle(.plain)
                        .accessibilityLabel("Вес порции в граммах")
                        .disabled(model.isAnalyzing)
                        .onChange(of: model.weight) { _, _ in if model.hasResult { model.rescale() } }
                }
                Text("г").font(.system(size: 22)).foregroundStyle(Palette.secondary)
            }.padding(16).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            Text(model.hasResult && model.weightMode == .ingredients ? "Сумма весов ингредиентов из состава ниже." : !model.weight.isEmpty && model.parsedWeight == nil
                 ? "Введите число от 0,1 до 20 000 г."
                 : "Вес готовой еды, без тарелки.")
                .font(.system(size: 10)).foregroundStyle(!model.weight.isEmpty && model.parsedWeight == nil ? Palette.orange : Palette.secondary)
                .padding(.top, -10)
            VStack(alignment: .leading, spacing: 8) {
                HStack { FieldLabel(title: "Что стоит учесть?"); Text("необязательно").font(.system(size: 9)).foregroundStyle(Palette.secondary.opacity(0.7)) }
                TextField("Например: курица, рис, 1 ч. л. масла", text: $model.notes, axis: .vertical)
                    .font(.system(size: 12)).lineLimit(2...3).inputSurface()
                    .disabled(model.isAnalyzing)
                    .onChange(of: model.notes) { _, new in if new.count > 8000 { model.notes = String(new.prefix(8000)) } }
            }
            if model.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Изучаем блюдо…").font(.system(size: 13, weight: .medium))
                        if model.provider == .local {
                            Text("На Mac это может занять несколько минут")
                                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    Button("Отмена") { model.cancelAnalysis() }.buttonStyle(.plain).foregroundStyle(Palette.green)
                }.padding(15).background(Palette.mint.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button { model.analyze() } label: {
                    Label(model.hasResult ? "Распознать заново" : "Рассчитать по фото", systemImage: "sparkles")
                }.buttonStyle(PrimaryButton()).disabled(model.photoData == nil || model.parsedWeight == nil)
            }
            Text(model.provider == .local
                 ? "\(OllamaService.displayName) · бесплатно на этом Mac."
                 : "Платный API: фото и уточнения отправляются в OpenAI.")
                .font(.system(size: 9)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, -7)
            if !model.hasResult {
                Button("Заполнить вручную") { model.startManual() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                    .frame(maxWidth: .infinity).disabled(model.isAnalyzing)
            }
        }
    }
    private var resultCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Eyebrow(text: model.isEstimate ? "Оценка готова · проверьте состав" : "Ваш расчёт")
                    Spacer()
                    if model.isEstimate { Label("Примерно", systemImage: "sparkles").font(.system(size: 10)).foregroundStyle(Palette.green) }
                }
                TextField("Название блюда", text: $model.dishName)
                    .font(.system(size: 24, weight: .semibold)).textFieldStyle(.plain)
                    .accessibilityLabel("Название блюда")
                if model.allIngredientsValid { MacroStrip(nutrients: model.total, estimated: model.isEstimate) }
                else {
                    Label("Заполните данные ингредиентов, чтобы увидеть итог.", systemImage: "pencil.line")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Divider().overlay(Palette.line)
                if !model.clarificationQuestions.isEmpty { PhotoClarificationsView() }
                IngredientEditor()
                if !model.assumptions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Что учтено приблизительно", systemImage: "info.circle").font(.system(size: 11, weight: .semibold))
                        ForEach(Array(model.assumptions.enumerated()), id: \.offset) { _, text in
                            Text("• \(text)").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        }
                    }.foregroundStyle(Palette.secondary).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Divider().overlay(Palette.line)
                HStack(alignment: .bottom, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(title: "Приём пищи")
                        Picker("Приём пищи", selection: $model.kind) {
                            ForEach(MealKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 130)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(title: "Дата и время")
                        ModernDateTimePicker(selection: $model.mealDate)
                    }
                    Spacer(minLength: 0)
                }
                Button { model.saveMeal() } label: {
                    Label(model.editingID == nil ? "Сохранить в дневник" : "Сохранить изменения", systemImage: "checkmark")
                }.buttonStyle(PrimaryButton()).disabled(!model.canSave)
                if model.hasClarificationAnswers {
                    Text("Сначала пересчитай блюдо с ответами или выбери «Оставить исходную оценку».")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                if model.parsedWeight == nil {
                    Text(model.weightMode == .ingredients ? "Укажите положительный вес каждого ингредиента. Сумма — до 20 000 г." : "Укажите вес порции вверху страницы.").font(.system(size: 11)).foregroundStyle(Palette.orange)
                }
            }.disabled(model.isAnalyzing)
        }
    }
    private var footnote: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "leaf").font(.system(size: 19, weight: .light)).foregroundStyle(Palette.green).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text("Фото подскажет состав. Вес уточнит порцию.").font(.system(size: 12, weight: .medium))
                Text("Масло, соусы и способ приготовления влияют на калории. Оценку по фото можно поправить перед сохранением.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.mint.opacity(0.28)).clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct IngredientEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var showProducts = false
    @State private var replacingID: UUID?
    @State private var initialGrams = ""
    @State private var savingProduct: SavedProduct?
    @State private var showCatalog = false
    @State private var catalogQuery = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Состав блюда").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    replacingID = nil; initialGrams = ""; showProducts = true
                } label: { Label("Мои продукты", systemImage: "shippingbox") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                Button {
                    replacingID = nil; initialGrams = "100"; catalogQuery = ""; showCatalog = true
                } label: { Label("Справочник", systemImage: "books.vertical") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                Button { model.drafts.append(IngredientDraft()) } label: { Label("Добавить", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
            }
            Picker("Как учитывать вес", selection: Binding(get: { model.weightMode }, set: { model.changeWeightMode($0) })) {
                ForEach(WeightMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text(model.weightMode == .ingredients ? "Вес порции складывается автоматически. Например: 70 г сосиски + 40 г сыра = 110 г." : "Общий вес задан вверху. При его изменении заполненные ингредиенты пересчитываются пропорционально.")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            Text("Калории и БЖУ — на 100 г продукта. Используйте данные для того состояния, в котором взвесили продукт.")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            HStack(spacing: 7) {
                Text("Продукт").frame(maxWidth: .infinity, alignment: .leading)
                Text("Вес, г").frame(width: 68)
                Text("ккал").frame(width: 63)
                Text("Б, г").frame(width: 53)
                Text("Ж, г").frame(width: 53)
                Text("У, г").frame(width: 53)
                Color.clear.frame(width: 24, height: 1)
            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            ForEach(model.drafts) { draft in
                let binding = model.binding(for: draft)
                VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    TextField("Название продукта", text: binding.name).inputSurface().frame(minWidth: 100)
                    field("Вес", text: binding.grams, width: 68)
                    field("Калории на 100 г", text: binding.calories, width: 63)
                    field("Белки на 100 г", text: binding.protein, width: 53)
                    field("Жиры на 100 г", text: binding.fat, width: 53)
                    field("Углеводы на 100 г", text: binding.carbs, width: 53)
                    Menu {
                        Button("Выбрать КБЖУ из справочника…") {
                            replacingID = draft.id; initialGrams = draft.grams
                            catalogQuery = draft.lookupQuery.isEmpty ? draft.name : draft.lookupQuery; showCatalog = true
                        }
                        Button("Выбрать из моих продуктов…") {
                            replacingID = draft.id; initialGrams = draft.grams; showProducts = true
                        }
                        Button("Сохранить в мои продукты…") {
                            if let ingredient = draft.ingredient { savingProduct = SavedProduct(name: ingredient.name, per100: ingredient.per100, source: ingredient.source) }
                        }.disabled(draft.ingredient == nil)
                        Button("Оценить калории по БЖУ") {
                            if let p = Numbers.parse(draft.protein), let f = Numbers.parse(draft.fat), let c = Numbers.parse(draft.carbs) {
                                binding.calories.wrappedValue = Numbers.input(4 * p + 9 * f + 4 * c); model.isEstimate = true
                            }
                        }.disabled(Numbers.parse(draft.protein) == nil || Numbers.parse(draft.fat) == nil || Numbers.parse(draft.carbs) == nil)
                        Divider()
                        Button("Удалить ингредиент", role: .destructive) { model.drafts.removeAll { $0.id == draft.id } }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                        .help("Действия с ингредиентом").accessibilityLabel("Действия: \(draft.name)")
                }.font(.system(size: 11))
                if !draft.lookupQuery.isEmpty && draft.calories.isEmpty {
                    Button {
                        replacingID = draft.id; initialGrams = draft.grams
                        catalogQuery = draft.lookupQuery.isEmpty ? draft.name : draft.lookupQuery; showCatalog = true
                    } label: { Label("Выбрать КБЖУ для «\(draft.name)» из базы", systemImage: "books.vertical") }
                        .buttonStyle(.link).font(.system(size: 11))
                    Text("Нейросеть определила продукт. Подтверди вариант в базе или заполни КБЖУ с упаковки.")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                if let source = draft.ingredient?.source {
                    Text("\(source.title) · \(source.detail)").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                }
            }
            if model.allIngredientsValid, let weight = model.parsedWeight, !model.weightMatches {
                HStack(spacing: 12) {
                    Text("Состав: \(Numbers.display(model.ingredientWeight)) г, порция: \(Numbers.display(weight)) г.")
                        .foregroundStyle(Palette.orange)
                    Spacer(minLength: 0)
                    Button("Распределить вес") { model.rescale() }.buttonStyle(.plain).foregroundStyle(Palette.green)
                }.font(.system(size: 11))
            } else if !model.allIngredientsValid {
                Text("Заполните все поля; для отсутствующих БЖУ укажите 0. Сумма БЖУ на 100 г не должна превышать 100 г.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            } else {
                Label("Итого: \(Numbers.display(model.ingredientWeight)) г", systemImage: "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.green)
            }
        }
        .sheet(isPresented: $showProducts) {
            ProductPicker(initialGrams: initialGrams) { product, grams in model.addProduct(product, grams: grams, replacing: replacingID) }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogPicker(query: catalogQuery, grams: initialGrams) { food, grams in model.applyCatalog(food, grams: grams, replacing: replacingID) }
        }
        .sheet(item: $savingProduct) { product in ProductEditor(product: product) }
    }
    private func field(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField("0", text: text).multilineTextAlignment(.trailing).inputSurface().frame(width: width)
            .accessibilityLabel(title)
    }
}
