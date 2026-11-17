import SwiftUI

// MARK: - Hex colors

extension Color {
    /// Creates a color from a 24-bit RGB hex value, e.g. `0x6366F1`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Design tokens

/// Centralized dark-first design system: palette, gradients, typography and motion.
enum Theme {
    // Base surfaces
    static let obsidianTop = Color(hex: 0x090A0F)
    static let obsidianBottom = Color(hex: 0x121521)

    // Accents
    static let indigo = Color(hex: 0x6366F1)
    static let violet = Color(hex: 0x8B5CF6)
    static let emerald = Color(hex: 0x10B981)
    static let cyan = Color(hex: 0x06B6D4)
    static let amber = Color(hex: 0xF59E0B)
    static let rose = Color(hex: 0xEC4899)

    // Text & strokes
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
    static let specular = Color.white.opacity(0.12)
    static let separator = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.08)
    static let rowBackground = Color.white.opacity(0.05)
    static let chipBackground = Color.white.opacity(0.07)

    // Gradient stops
    static let primaryColors: [Color] = [indigo, violet]
    static let successColors: [Color] = [emerald, cyan]
    static let legendaryColors: [Color] = [amber, rose]

    /// Obsidian vertical backdrop used behind every screen and sheet.
    static var background: LinearGradient {
        LinearGradient(colors: [obsidianTop, obsidianBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Electric Indigo → Violet: primary actions and XP progress.
    static var primaryGradient: LinearGradient { diagonal(primaryColors) }
    /// Emerald → Cyan: completed states and leisure unlocks.
    static var successGradient: LinearGradient { diagonal(successColors) }
    /// Amber → Rose: rare and legendary badges.
    static var legendaryGradient: LinearGradient { diagonal(legendaryColors) }

    static func diagonal(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func horizontal(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    static func vertical(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
    }

    // Typography: rounded for numbers & headers, standard SF Pro elsewhere.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    static func rounded(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // Motion
    static var spring: Animation { .spring(response: 0.42, dampingFraction: 0.78) }
    static var bouncy: Animation { .spring(response: 0.5, dampingFraction: 0.6) }
}

// MARK: - Glass card

/// Elevated glass surface: ultra-thin dark material, 1px specular top edge, soft ambient shadow.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? .white).opacity(tint == nil ? 0.03 : 0.10)))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.specular, Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Obsidian gradient behind a List / Form / ScrollView.
    func themedScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Translucent row surface for List / Form rows on the obsidian background.
    func glassRow() -> some View {
        self
            .listRowBackground(Theme.rowBackground)
            .listRowSeparatorTint(Theme.separator)
    }
}

// MARK: - Shared components

/// Capsule progress bar with a glowing gradient fill.
struct GradientProgressBar: View {
    var value: Double
    var colors: [Color] = Theme.primaryColors
    var height: CGFloat = 8

    var body: some View {
        let clamped = min(max(value, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.horizontal(colors))
                    .frame(width: clamped > 0 ? max(height, proxy.size.width * clamped) : 0)
                    .shadow(color: (colors.last ?? .white).opacity(0.55), radius: 6)
            }
        }
        .frame(height: height)
        .animation(Theme.spring, value: clamped)
        .accessibilityHidden(true)
    }
}

/// Small capsule showing an icon, an animated number and a unit.
struct StatPill: View {
    let icon: String
    let value: Int
    let unit: String
    var colors: [Color] = Theme.primaryColors

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.diagonal(colors))
            Text("\(value)")
                .font(Theme.rounded(.subheadline))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.chipBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .animation(Theme.spring, value: value)
    }
}

/// Uppercase section title with an optional subtitle, for ScrollView-based screens.
struct SectionTitle: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Circular icon tile filled with a gradient.
struct GradientIcon: View {
    let systemName: String
    var colors: [Color] = Theme.primaryColors
    var size: CGFloat = 40
    var isActive = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textTertiary))
            .frame(width: size, height: size)
            .background {
                Circle().fill(isActive ? AnyShapeStyle(Theme.diagonal(colors)) : AnyShapeStyle(Theme.chipBackground))
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(isActive ? 0.25 : 0.08), lineWidth: 1))
            .shadow(color: isActive ? (colors.last ?? .clear).opacity(0.45) : .clear, radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}

#Preview("Theme") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Gradients", subtitle: "Primary, success, legendary")
            HStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.primaryGradient)
                RoundedRectangle(cornerRadius: 14).fill(Theme.successGradient)
                RoundedRectangle(cornerRadius: 14).fill(Theme.legendaryGradient)
            }
            .frame(height: 60)

            VStack(alignment: .leading, spacing: 12) {
                Text("Glass card").font(Theme.rounded(.title2))
                GradientProgressBar(value: 0.62)
                GradientProgressBar(value: 0.35, colors: Theme.successColors)
                HStack {
                    StatPill(icon: "star.fill", value: 325, unit: "XP")
                    StatPill(icon: "leaf.fill", value: 275, unit: "pts", colors: Theme.successColors)
                }
            }
            .padding(18)
            .glassCard()

            HStack {
                GradientIcon(systemName: "cup.and.saucer.fill", colors: Theme.successColors)
                GradientIcon(systemName: "gamecontroller.fill")
                GradientIcon(systemName: "sun.haze.fill", colors: Theme.legendaryColors)
                GradientIcon(systemName: "lock.fill", isActive: false)
            }
        }
        .padding()
    }
    .themedScreen()
    .preferredColorScheme(.dark)
}
