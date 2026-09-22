import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct TarelkaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = AppearanceChoice.light.rawValue
    var body: some Scene {
        Window("Тарелка", id: "main") {
            RootView().environmentObject(model).environmentObject(model.personal).environmentObject(model.coach)
                .preferredColorScheme((AppearanceChoice(rawValue: appearance) ?? .light).scheme)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .tint(Palette.green)
                .disclosureGroupStyle(ExpandableSectionStyle())
                .frame(minWidth: 1020, minHeight: 740)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 860)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") { model.screen = .settings }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button("Добавить напиток…") { model.drinkEditor = DrinkDraft() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Добавить фото…") { model.screen = .newMeal; model.choosePhoto() }
                    .keyboardShortcut("o").disabled(model.isAnalyzing)
                Button("Вставить фото") { model.screen = .newMeal; model.pastePhoto() }
                    .keyboardShortcut("v", modifiers: [.command, .shift]).disabled(model.isAnalyzing)
                Button("Сохранить блюдо") { model.saveMeal() }.keyboardShortcut("s").disabled(!model.canSave)
            }
        }
    }
}
