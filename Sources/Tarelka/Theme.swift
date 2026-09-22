import SwiftUI
import NutritionCore

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system = "Как в macOS", light = "Светлая", dark = "Тёмная"
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
}

enum Palette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xF0F4FB, 0x101723)
    static let surface = adaptive(0xFFFFFF, 0x202D40)
    static let edge = adaptive(0xFFFFFF, 0x52637B)
    static let sidebar = adaptive(0xD4EBEB, 0x20333E)
    static let green = adaptive(0x1F66C7, 0x78B7FF)
    static let mint = adaptive(0xC2E8FA, 0x24455E)
    static let ink = adaptive(0x1F293D, 0xF0F4FC)
    static let secondary = adaptive(0x59667D, 0xB1BFD2)
    static let line = adaptive(0xC4CFE0, 0x52627A)
    static let orange = adaptive(0xC94F26, 0xFFAA78)
    static let blue = adaptive(0x336BCF, 0x86B8FF)
    static let violet = adaptive(0x7352B8, 0xC6AEFF)
    static let successBanner = adaptive(0xDEF5FF, 0x16384B)
    static let errorBanner = adaptive(0xFFF2E6, 0x492E25)
}
struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            let glow = colorScheme == .dark ? 0.16 : 1.0
            let size = max(geometry.size.width, geometry.size.height)
            ZStack {
                Palette.background
                RadialGradient(colors: [Color(red: 0.50, green: 0.77, blue: 0.98).opacity(0.52 * glow), .clear],
                               center: .topLeading, startRadius: 0, endRadius: size * 0.7)
                RadialGradient(colors: [Color(red: 0.73, green: 0.65, blue: 0.95).opacity(0.36 * glow), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: size * 0.6)
                RadialGradient(colors: [Color(red: 0.55, green: 0.91, blue: 0.84).opacity(0.32 * glow), .clear],
                               center: .trailing, startRadius: 0, endRadius: size * 0.55)
                LinearGradient(colors: [Palette.surface.opacity(0.22), .clear, Palette.surface.opacity(0.30)],
                               startPoint: .top, endPoint: .bottom)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        // Static colour under native glass; no animation loop or repeated backdrop invalidation.
    }
}
struct LiquidSurface: ViewModifier {
    var radius: CGFloat
    var tint: Color
    var interactive: Bool
    var clear: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                RoundedRectangle(cornerRadius: radius).fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: radius).fill(tint))
            }
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.line.opacity(0.8)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect((clear ? Glass.clear : Glass.regular).tint(tint).interactive(interactive), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .background(tint, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.edge.opacity(0.75)))
        }
    }
}
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 0) { content } }
        else { content }
    }
}
struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.brightness(hovering ? 0.025 : 0).overlay {
            RoundedRectangle(cornerRadius: 13).stroke(Palette.green.opacity(hovering ? 0.35 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
    }
}
struct Arrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    var delay: Double
    func body(content: Content) -> some View {
        content.opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 16)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.9).delay(min(delay, 0.22))) { visible = true } }
    }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? (colorScheme == .dark ? Color(red: 0.07, green: 0.13, blue: 0.22) : .white) : Palette.secondary)
            .padding(.horizontal, 19).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(enabled ? Palette.green : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .liquidSurface(radius: 16, tint: enabled ? Palette.green : Palette.line.opacity(0.4), interactive: enabled)
            .opacity(enabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
struct SoftButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Palette.ink : Palette.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .liquidSurface(radius: 14, interactive: enabled)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
struct Card<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24).fill(Palette.surface.opacity(reduceTransparency ? 1 : 0.65))
                    .shadow(color: Palette.ink.opacity(0.025), radius: 16, y: 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.edge.opacity(0.85)))
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.9).foregroundStyle(Palette.secondary) }
}
struct FieldLabel: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary) }
}
struct MacroStrip: View {
    let nutrients: Nutrients
    var estimated = false
    var calorieCaption = "ккал в порции"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(estimated ? "≈ " : "")\(Numbers.display(nutrients.calories, decimals: 0))")
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit().animatedNumber(nutrients.calories)
                Text(calorieCaption).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            macro("Белки", value: nutrients.protein, color: Palette.green)
            macro("Жиры", value: nutrients.fat, color: Palette.orange)
            macro("Углеводы", value: nutrients.carbs, color: Palette.blue)
        }.foregroundStyle(Palette.ink)
    }
    private func macro(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(title).font(.system(size: 11)) }.foregroundStyle(Palette.secondary)
            Text("\(Numbers.display(value)) г").font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().animatedNumber(value)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct AnimatedNumber: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.contentTransition(.numericText(value: value)).animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value)
    }
}
struct EnergyRing: View {
    let budget: DayBudget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            Circle().fill(Palette.surface.opacity(0.6)).padding(25).shadow(color: Palette.green.opacity(0.08), radius: 20)
            ring(progress: min(budget.eaten / max(budget.target, 1), 1), colors: [Palette.green, Color(red: 0.24, green: 0.79, blue: 0.63)], width: 13)
            ring(progress: min(budget.creditedActivity / max(budget.base, 1), 1), colors: [Palette.blue, Color.cyan], width: 6).padding(20)
            VStack(spacing: 6) {
                Image(systemName: budget.remaining >= 0 ? "leaf.fill" : "circle.dotted").font(.system(size: 19)).foregroundStyle(Palette.green)
                Text(Numbers.display(abs(budget.remaining), decimals: 0)).font(.system(size: 43, weight: .semibold, design: .rounded)).tracking(-2)
                    .monospacedDigit().animatedNumber(abs(budget.remaining))
                Text(budget.remaining >= 0 ? "ккал осталось" : "ккал сверх ориентира").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.padding(32)
        }.frame(width: 232, height: 232).accessibilityElement(children: .combine)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
    private func ring(progress: Double, colors: [Color], width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(colors[0].opacity(0.10), lineWidth: width)
            Circle().trim(from: 0, to: appeared || reduceMotion ? max(0, progress) : 0)
                .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90)).shadow(color: colors[0].opacity(0.18), radius: 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
        }.padding(width / 2)
    }
}
extension View {
    func liquidSurface(radius: CGFloat = 18, tint: Color = .clear, interactive: Bool = false, clear: Bool = false) -> some View {
        modifier(LiquidSurface(radius: radius, tint: tint, interactive: interactive, clear: clear))
    }
    func arrive(delay: Double = 0) -> some View { modifier(Arrival(delay: delay)) }
    func animatedNumber(_ value: Double) -> some View { modifier(AnimatedNumber(value: value)) }
    func inputSurface() -> some View {
        self.textFieldStyle(.plain).padding(12).background(Palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line.opacity(0.75)))
    }
}

/// The whole heading is a keyboard-accessible button, not just the small chevron.
struct ExpandableSectionStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    configuration.label
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                        .font(.system(size: 11, weight: .semibold))
                }.padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Развёрнуто" : "Свёрнуто")
            if configuration.isExpanded { configuration.content }
        }
    }
}
