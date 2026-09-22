import SwiftUI
import NutritionCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var personal: PersonalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigationSpace
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 228).padding(.leading, 16).padding(.top, 35).padding(.bottom, 16)
            VStack(spacing: 0) {
                if let error = model.storageError { banner(error, isError: true, dismissible: false) }
                if let error = personal.storageError { banner(error, isError: true, dismissible: false) }
                if let error = personal.error {
                    HStack { Text(error).font(.system(size: 12)); Spacer(); Button("Закрыть") { personal.error = nil } }
                        .padding(13).foregroundStyle(Palette.orange).padding(.horizontal, 20)
                }
                if let error = model.errorMessage { banner(error, isError: true) }
                if let notice = model.notice { banner(notice, isError: false) }
                Group {
                    switch model.screen {
                    case .newMeal: NewMealView()
                    case .diary: DiaryView()
                    case .products: ProductsView()
                    case .day: DayView()
                    case .week: WeekReportView()
                    case .coach: CoachView()
                    case .recipes: RecipeView(store: model.recipes)
                    case .settings: PreferencesView()
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: model.screen)
            }.padding(.top, 27)
        }.background { LiquidBackground() }.foregroundStyle(Palette.ink)
            .task { await model.reminders.restore() }
            .onReceive(NotificationCenter.default.publisher(for: .openMealFromReminder)) { _ in
                model.screen = .newMeal; NSApp.activate(ignoringOtherApps: true)
            }
            .task(id: model.notice) {
                guard let notice = model.notice else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if model.notice == notice { model.notice = nil }
            }
            .sheet(item: $model.drinkEditor) { draft in DrinkEditor(draft: draft) }
            .onChange(of: model.screen) { _, screen in
                if screen != .coach && screen != .day { model.coach.cancel() }
            }
            .onChange(of: model.isAnalyzing) { _, active in if active { model.coach.cancel() } }
            .onChange(of: model.drinkEditor?.id) { _, id in if id != nil { model.coach.cancel() } }
            .task {
                while !Task.isCancelled {
                    personal.refreshLinkedFile()
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                }
            }
    }
    private var sidebar: some View {
        GeometryReader { geometry in
            ScrollView { sidebarContent(compact: geometry.size.height < 800).frame(minHeight: geometry.size.height) }.scrollIndicators(.hidden)
        }
    }
    private func sidebarContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 21, weight: .medium)).foregroundStyle(Palette.green)
                    .frame(width: 43, height: 43)
                    .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Тарелка").font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                    Text("Твой дневник питания").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 7).padding(.bottom, 22)
            VStack(spacing: 5) {
                navigation("Мой день", symbol: "circle.dotted.circle.fill", screen: .day)
                navigation("Дневник питания", symbol: "square.grid.2x2", screen: .diary)
                navigation("Отчёт за неделю", symbol: "chart.bar.xaxis", screen: .week)
                navigation("Мои продукты", symbol: "shippingbox", screen: .products)
                navigation("Помощник", symbol: "sparkles", screen: .coach)
                navigation("Что приготовить", symbol: "carrot", screen: .recipes)
            }
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 12)
            VStack(spacing: 5) {
                navigation("Новое блюдо", symbol: "plus.circle.fill", screen: .newMeal)
                Button { model.drinkEditor = DrinkDraft() } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "cup.and.saucer").font(.system(size: 16)).frame(width: 22)
                        Text("Добавить напиток").font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).padding(.vertical, 11).contentShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).foregroundStyle(Palette.secondary).modifier(HoverLift())
            }
            Spacer(minLength: 18)
            todayCard(compact: compact)
            navigation("Настройки", symbol: "slider.horizontal.3", screen: .settings).padding(.top, 14)
            HStack(spacing: 5) {
                Circle().fill(model.provider == .local || model.hasKey ? Color.teal : Palette.orange).frame(width: 5, height: 5)
                Text(model.provider == .local ? "Локально · бесплатно" : "OpenAI · платный API")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(.leading, 12).padding(.top, 15)
        }.padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 20)
            .frame(maxHeight: .infinity)
            .liquidSurface(radius: 28, tint: .white.opacity(0.12), clear: true)
    }
    private func navigation(_ title: String, symbol: String, screen: Screen) -> some View {
        let selected = model.screen == screen
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) { model.screen = screen }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 22)
                    .foregroundStyle(selected ? Palette.green : Palette.secondary)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if selected { Circle().fill(Palette.green).frame(width: 4, height: 4) }
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 14).fill(Palette.surface.opacity(0.82))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.edge.opacity(0.95)))
                            .matchedGeometryEffect(id: "selection", in: navigationSpace)
                            .shadow(color: Palette.ink.opacity(0.06), radius: 8, y: 3)
                    }
                }.contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).modifier(HoverLift())
    }
    private func todayCard(compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let total = model.total(on: timeline.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Сегодня").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(model.meals(on: timeline.date).count) записей").font(.system(size: 10))
                }.foregroundStyle(Palette.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Numbers.display(total.calories, decimals: 0))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).animatedNumber(total.calories)
                    Text("ккал").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                if !compact { HStack {
                    miniMacro("Б", total.protein); Spacer(); miniMacro("Ж", total.fat); Spacer(); miniMacro("У", total.carbs)
                } }
                if let budget = personal.data.budget(on: timeline.date, eaten: total.calories) {
                    Text("\(budget.remaining >= 0 ? "Осталось" : "Сверх ориентира") \(Numbers.display(abs(budget.remaining), decimals: 0)) ккал")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                    if budget.creditsActivity && !compact {
                        Label(budget.awaitingActivity ? "Ждём данные часов" : "+\(Numbers.display(budget.creditedActivity, decimals: 0)) ккал активности", systemImage: "applewatch")
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface.opacity(0.36), in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(Palette.edge.opacity(0.55)))
        }
    }
    private func miniMacro(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(Palette.secondary)
            Text(Numbers.display(value, decimals: 0)).fontWeight(.medium)
        }.font(.system(size: 10))
    }
    private func banner(_ message: String, isError: Bool, dismissible: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if dismissible {
                Button {
                    if isError { model.errorMessage = nil } else { model.notice = nil }
                } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).accessibilityLabel("Закрыть сообщение")
            }
        }.padding(13).foregroundStyle(isError ? Palette.orange : Palette.green)
            .background(isError ? Palette.errorBanner : Palette.successBanner)
            .clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 32).padding(.bottom, 8)
    }
}
