import SwiftUI

/// Only this small circle redraws while listening; no full-window blur or model inference.
struct VoiceOrb: View {
    let active: Bool
    @ObservedObject var activity: SpeechActivity
    private var level: Double { activity.level }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || reduceMotion)) { timeline in
            let time = active && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            let breath = active && !reduceMotion ? sin(time * 1.5) : 0
            ZStack {
                Circle().fill(RadialGradient(colors: [Palette.blue.opacity(0.17), .clear], center: .center, startRadius: 65, endRadius: 126))
                    .frame(width: 252, height: 252)
                Circle().stroke(Palette.blue.opacity(0.12), lineWidth: 1).frame(width: 216, height: 216)
                    .scaleEffect(1 + (reduceMotion ? 0 : level * 0.08))
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.79, green: 0.95, blue: 1), Color(red: 0.17, green: 0.55, blue: 0.97), Color(red: 0.24, green: 0.24, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Ellipse().fill(RadialGradient(colors: [.white.opacity(0.95), Color.cyan.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 96))
                        .frame(width: 200, height: 110).rotationEffect(.degrees(time * 13)).offset(x: -22, y: -35 + breath * 9)
                    Ellipse().fill(LinearGradient(colors: [.clear, Color(red: 0.6, green: 0.4, blue: 0.95).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 230, height: 80).rotationEffect(.degrees(-28 + breath * 17)).offset(x: 12, y: 48)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.85), .clear], center: .topLeading, startRadius: 0, endRadius: 135))
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.1), .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                }
                .frame(width: 170, height: 170).clipShape(Circle())
                .scaleEffect(1 + (reduceMotion ? 0 : level * 0.10 + breath * 0.018))
                .shadow(color: Palette.blue.opacity(0.18), radius: 16, y: 12)
            }.frame(width: 252, height: 252)
        }.accessibilityHidden(true)
    }
}

struct VoiceDictationView: View {
    @ObservedObject var speech: SpeechInput
    let foods: String
    let onStart: () -> Void
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Bool { speech.recording || speech.requesting }
    private var title: String {
        if speech.requesting { return "Включаю микрофон" }
        if speech.recording { return "Я слушаю" }
        if speech.error != nil { return "Микрофон на паузе" }
        return speech.elapsed > 0 || !speech.transcript.isEmpty ? "Продукты записаны" : "Что есть у тебя дома?"
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("ГОЛОСОВОЙ ВВОД", systemImage: "waveform").font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(Palette.secondary)
                Spacer()
                Button(action: onDone) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).liquidSurface(radius: 14).accessibilityLabel("Закрыть диктовку и сохранить продукты")
            }
            VoiceOrb(active: speech.recording, activity: speech.activity).padding(.top, 4)
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.6).foregroundStyle(Palette.ink)
            Text(speech.recording ? "Говори в своём темпе. Паузы — это нормально." : "Называй продукты и количество — я запишу.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 8)
            HStack(spacing: 7) {
                Circle().fill(speech.recording ? Palette.green : Palette.secondary.opacity(0.4)).frame(width: 5, height: 5)
                Text(speech.recording ? String(format: "Слушаю · 0:%02d / 1:00", speech.elapsed) : "На этом Mac · без отправки аудио")
                    .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Palette.secondary)
            }.padding(.top, 13).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 8) {
                Text("ТВОИ ПРОДУКТЫ").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.secondary)
                ScrollView {
                    Text(foods.isEmpty ? "Например: картошка, два яйца и немного сыра…" : foods)
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(foods.isEmpty ? Palette.secondary : Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 68)
            }.padding(18).frame(maxWidth: .infinity).liquidSurface(radius: 20)
            if let error = speech.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            HStack(spacing: 12) {
                Button(action: { active ? speech.stop() : onStart() }) {
                    Label(speech.requesting ? "Отменить" : speech.recording ? "Пауза" : speech.transcript.isEmpty ? "Начать диктовку" : "Продолжить", systemImage: active ? "pause.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(SoftButton())
                Button("Готово", action: onDone).buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
            }.padding(.top, 20)
            Text("Список сохраняется по мере речи. Его можно исправить после диктовки.")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 12)
        }
        .padding(28).frame(width: 520)
        .background { LiquidBackground() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: speech.recording)
        .onDisappear { speech.stop() }
    }
}
