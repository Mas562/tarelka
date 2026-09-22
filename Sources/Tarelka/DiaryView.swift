import SwiftUI
import NutritionCore

struct DiaryView: View {
    @EnvironmentObject var model: AppModel
    @State private var deleteTarget: Meal?
    @State private var editTarget: Meal?
    @State private var confirmReplace = false
    private var dayMeals: [Meal] { model.meals(on: model.selectedDay) }
    var body: some View {
        let meals = dayMeals
        let total = meals.reduce(Nutrients()) { $0 + $1.total }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Все записи")
                        Text("Дневник питания").font(.system(size: 31, weight: .semibold)).tracking(-0.9)
                        Text("Все порции и их состав — в одном месте.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Блюдо") { model.screen = .newMeal }
                        Button("Напиток") { model.drinkEditor = DrinkDraft(date: model.selectedDay) }
                    } label: { Label("Добавить", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack(spacing: 13) {
                    Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SoftButton()).accessibilityLabel("Предыдущий день")
                    ModernDatePicker(title: "Выбрать день", selection: $model.selectedDay)
                    Button { moveDay(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SoftButton()).accessibilityLabel("Следующий день")
                    Button("Сегодня") { model.selectedDay = Date() }.buttonStyle(.plain).foregroundStyle(Palette.green).font(.system(size: 12))
                    Spacer()
                    Text("Записей: \(meals.count)").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow(text: "Всего за день")
                        MacroStrip(nutrients: total,
                                   estimated: meals.contains(where: \.isEstimate), calorieCaption: "ккал за день")
                    }
                }
                if meals.isEmpty { emptyState }
                else {
                    ForEach(meals) { meal in mealCard(meal) }
                    Text("Значения по фото приблизительные. Нажмите на запись, чтобы уточнить состав, вес или объём.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 32).padding(.top, 23).padding(.bottom, 36).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
        .alert("Удалить запись из дневника?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Удалить", role: .destructive) { if let meal = deleteTarget { model.deleteMeal(meal) }; deleteTarget = nil }
            Button("Отмена", role: .cancel) { deleteTarget = nil }
        } message: { Text(deleteTarget?.name ?? "") }
        .confirmationDialog("Открыть запись вместо текущего черновика?", isPresented: $confirmReplace) {
            Button("Открыть запись", role: .destructive) { if let meal = editTarget { model.edit(meal) }; editTarget = nil }
            Button("Оставить черновик", role: .cancel) { editTarget = nil }
        } message: { Text("Несохранённые изменения в форме будут потеряны.") }
    }
    private func moveDay(_ offset: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDay) { model.selectedDay = date }
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 39, weight: .ultraLight)).foregroundStyle(Palette.green)
                .frame(width: 100, height: 100).background(Palette.mint.opacity(0.6)).clipShape(Circle())
            Text("Здесь появятся блюда и напитки").font(.system(size: 20, weight: .medium)).tracking(-0.4)
            Text("За этот день пока нет записей.\nДобавьте первую порцию, когда будете готовы.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Button("Добавить блюдо") { model.screen = .newMeal }.buttonStyle(SoftButton())
        }.padding(.vertical, 46).frame(maxWidth: .infinity)
    }
    private func mealCard(_ meal: Meal) -> some View {
        let total = meal.total
        return Card(padding: 17) {
            HStack(spacing: 17) {
                Button { open(meal) } label: {
                    HStack(spacing: 17) {
                        MealThumbnail(url: model.repository.photoURL(meal.photoFilename), symbol: meal.isDrink ? "cup.and.saucer" : "fork.knife")
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 7) {
                                Text(meal.kind.rawValue.uppercased()).tracking(0.8)
                                Text("·")
                                Text(meal.date, style: .time)
                            }.font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.secondary)
                            Text(meal.name).font(.system(size: 17, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text("\(Numbers.display(meal.weight)) \(meal.unit.symbol)  ·  Б \(Numbers.display(total.protein))  Ж \(Numbers.display(total.fat))  У \(Numbers.display(total.carbs))")
                                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 10)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("\(meal.isEstimate ? "≈ " : "")\(Numbers.display(total.calories, decimals: 0))")
                                .font(.system(size: 25, weight: .medium, design: .rounded))
                            Text("ккал").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Открыть \(meal.name)")
                Menu {
                    Button("Изменить") { open(meal) }
                    Button("Удалить", role: .destructive) { deleteTarget = meal }
                } label: { Image(systemName: "ellipsis").frame(width: 18, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Действия с записью")
            }
        }
    }
    private func open(_ meal: Meal) {
        if meal.isDrink { model.edit(meal); return }
        if model.hasDraft { editTarget = meal; confirmReplace = true }
        else { model.edit(meal) }
    }
}
