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
    // Warm porcelain and graphite with one deep emerald accent and a champagne detail colour.
    // Every text colour keeps at least 4.5:1 contrast on its background in both themes.
    static let background = adaptive(0xF5F3EF, 0x0E1116)
    static let surface = adaptive(0xFFFFFF, 0x191E26)
    static let edge = adaptive(0xFFFFFF, 0x363F4C)
    static let sidebar = adaptive(0xEDEAE4, 0x151A21)
    static let green = adaptive(0x0B6E5F, 0x5ED1B5)
    static let mint = adaptive(0xDDEFE9, 0x163B34)
    static let ink = adaptive(0x16191E, 0xF3F0EA)
    static let secondary = adaptive(0x666A72, 0xA3A8B0)
    static let line = adaptive(0xE2DDD4, 0x2E3540)
    static let orange = adaptive(0xB4542B, 0xF2A47C)
    static let blue = adaptive(0x3F56C6, 0x93A8FF)
    static let violet = adaptive(0x6A4FBF, 0xBCA9FF)
    static let gold = adaptive(0x8A6A2E, 0xE2C07E)
    static let successBanner = adaptive(0xE4F2EC, 0x13342D)
    static let errorBanner = adaptive(0xFAEEE6, 0x43291F)
    /// Accent gradient for primary actions, rings and the app mark.
    static let accentGradient = LinearGradient(colors: [adaptive(0x12806E, 0x74DEC4), adaptive(0x0A5C50, 0x3FB89B)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// One radius scale, always with continuous (squircle) corners.
enum Radius {
    static let card: CGFloat = 26
    static let control: CGFloat = 14
    static let field: CGFloat = 12
}
struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            let dark = colorScheme == .dark
            let size = max(geometry.size.width, geometry.size.height)
            // A quiet champagne, sage and lavender light for the glass to refract — never a loud gradient.
            ZStack {
                Palette.background
                RadialGradient(colors: [(dark ? Color(red: 0.36, green: 0.30, blue: 0.20) : Color(red: 0.98, green: 0.88, blue: 0.72))
                                            .opacity(dark ? 0.32 : 0.55), .clear],
                               center: .topLeading, startRadius: 0, endRadius: size * 0.62)
                RadialGradient(colors: [(dark ? Color(red: 0.08, green: 0.34, blue: 0.29) : Color(red: 0.70, green: 0.89, blue: 0.81))
                                            .opacity(dark ? 0.38 : 0.45), .clear],
                               center: UnitPoint(x: 1, y: 0.35), startRadius: 0, endRadius: size * 0.55)
                RadialGradient(colors: [(dark ? Color(red: 0.22, green: 0.20, blue: 0.40) : Color(red: 0.84, green: 0.82, blue: 0.97))
                                            .opacity(dark ? 0.30 : 0.40), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: size * 0.55)
                LinearGradient(colors: [.white.opacity(dark ? 0.015 : 0.25), .clear, Palette.background.opacity(0.35)],
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
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background { shape.fill(Palette.surface).overlay(shape.fill(tint)) }
                .overlay(shape.stroke(Palette.line))
        } else if #available(macOS 26.0, *) {
            content.glassEffect((clear ? Glass.clear : Glass.regular).tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background(tint, in: shape)
                .overlay(shape.stroke(Palette.edge.opacity(0.75)))
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
        content.background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.ink.opacity(hovering ? 0.045 : 0))
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
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        configuration.label.font(.system(size: 13, weight: .semibold)).tracking(0.1)
            .foregroundStyle(enabled ? (colorScheme == .dark ? Color(red: 0.03, green: 0.12, blue: 0.10) : .white) : Palette.secondary)
            .padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background {
                if enabled {
                    // Lit from above: accent gradient, a hairline highlight and a soft coloured shadow.
                    shape.fill(Palette.accentGradient)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.28), lineWidth: 0.8))
                        .shadow(color: Palette.green.opacity(configuration.isPressed ? 0.12 : 0.26), radius: configuration.isPressed ? 6 : 14, y: configuration.isPressed ? 3 : 7)
                }
            }
            .liquidSurface(radius: 16, tint: enabled ? Palette.green.opacity(0.35) : Palette.line.opacity(0.4), interactive: enabled)
            .opacity(enabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
struct SoftButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Palette.ink : Palette.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .liquidSurface(radius: Radius.control, tint: Palette.surface.opacity(0.18), interactive: enabled)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
struct Card<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let dark = colorScheme == .dark
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Two shadows (contact + ambient) give real depth without a heavy drop shadow.
                shape.fill(Palette.surface.opacity(reduceTransparency ? 1 : (dark ? 0.72 : 0.78)))
                    .shadow(color: .black.opacity(dark ? 0.28 : 0.035), radius: 1.5, y: 1)
                    .shadow(color: .black.opacity(dark ? 0.32 : 0.055), radius: 24, y: 14)
            }
            .overlay {
                // A light catching the top edge, fading towards the bottom.
                shape.strokeBorder(LinearGradient(colors: [Palette.edge.opacity(dark ? 0.75 : 1), Palette.edge.opacity(dark ? 0.2 : 0.55)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.gold)
    }
}
struct FieldLabel: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary) }
}
/// A tinted squircle behind an SF Symbol: one consistent icon treatment across the app.
struct IconTile: View {
    let symbol: String
    var color: Color = Palette.green
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.44, weight: .medium)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).strokeBorder(color.opacity(0.12), lineWidth: 0.8))
    }
}
struct MacroStrip: View {
    let nutrients: Nutrients
    var estimated = false
    var calorieCaption = "ккал в порции"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(estimated ? "≈ " : "")\(Numbers.display(nutrients.calories, decimals: 0))")
                    .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.2).monospacedDigit().animatedNumber(nutrients.calories)
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
            Text("\(Numbers.display(value)) г").font(.system(size: 21, weight: .semibold, design: .rounded)).tracking(-0.3).monospacedDigit().animatedNumber(value)
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
            ring(progress: min(budget.eaten / max(budget.target, 1), 1), colors: [Palette.green, Color(red: 0.36, green: 0.78, blue: 0.66)], width: 13)
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
        self.textFieldStyle(.plain).padding(12)
            .background(Palette.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
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
                    .background(Palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Развёрнуто" : "Свёрнуто")
            if configuration.isExpanded { configuration.content }
        }
    }
}
