import SwiftUI

/// Pure-SwiftUI award emblem: a tier-metal rim around a glowing gradient core,
/// with layered SF Symbols and a specular highlight.
///
/// - Bronze / Silver / Gold: metallic angular rims over the category gradient.
/// - Obsidian: near-black core, amber→rose symbol and a slowly rotating legendary rim.
/// - Locked: desaturated with a lock pip. Secret + locked: shows a "?" glyph only.
struct BadgeMedallionView: View {
    let iconName: String
    let category: AwardCategory
    let tier: AwardTier
    var isUnlocked: Bool = true
    var isSecret: Bool = false
    var size: CGFloat = 72

    @State private var rimRotation: Double = 0

    private var isHidden: Bool { isSecret && !isUnlocked }

    var body: some View {
        ZStack {
            if isUnlocked {
                glow
            }

            // Tier rim
            Circle()
                .fill(AngularGradient(colors: tier.rimColors, center: .center))
                .rotationEffect(.degrees(rimRotation))
                .frame(width: size, height: size)

            // Core
            Circle()
                .fill(coreStyle)
                .frame(width: size * 0.84, height: size * 0.84)

            // Inner ring
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: max(1, size * 0.014))
                .frame(width: size * 0.73, height: size * 0.73)

            // Backdrop symbol (category watermark)
            if !isHidden {
                Image(systemName: category.iconName)
                    .font(.system(size: size * 0.46, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.08))
                    .offset(x: size * 0.13, y: size * 0.12)
                    .frame(width: size * 0.84, height: size * 0.84)
                    .clipShape(Circle())
            }

            // Main symbol
            Image(systemName: isHidden ? "questionmark" : iconName)
                .font(.system(size: size * (isHidden ? 0.4 : 0.34), weight: .bold, design: .rounded))
                .foregroundStyle(symbolStyle)
                .shadow(color: .black.opacity(0.4), radius: size * 0.03, y: size * 0.02)

            // Specular highlight
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.58, height: size * 0.32)
                .offset(y: -size * 0.22)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .saturation(isUnlocked ? 1 : 0)
        .brightness(isUnlocked ? 0 : -0.1)
        .opacity(isUnlocked ? 1 : 0.62)
        .overlay(alignment: .bottomTrailing) {
            if !isUnlocked {
                lockPip
            }
        }
        .onAppear(perform: startRimAnimationIfNeeded)
        .onChange(of: isUnlocked) { startRimAnimationIfNeeded() }
        .accessibilityHidden(true)
    }

    // MARK: Layers

    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tier.glowColor.opacity(0.55), tier.glowColor.opacity(0)],
                    center: .center,
                    startRadius: size * 0.3,
                    endRadius: size * 0.8
                )
            )
            .frame(width: size * 1.6, height: size * 1.6)
            .allowsHitTesting(false)
    }

    private var lockPip: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.15, weight: .bold))
            .foregroundStyle(.white)
            .padding(size * 0.075)
            .background(Circle().fill(Color(hex: 0x2A2D3A)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var coreStyle: AnyShapeStyle {
        if isHidden {
            return AnyShapeStyle(RadialGradient(
                colors: [Color(hex: 0x262A3B), Color(hex: 0x0B0C12)],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 0,
                endRadius: size * 0.6
            ))
        }
        if tier == .obsidian {
            return AnyShapeStyle(RadialGradient(
                colors: [Color(hex: 0x2E2645), Color(hex: 0x07070C)],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 0,
                endRadius: size * 0.6
            ))
        }
        return AnyShapeStyle(RadialGradient(
            colors: category.colors,
            center: UnitPoint(x: 0.3, y: 0.25),
            startRadius: 0,
            endRadius: size * 0.75
        ))
    }

    private var symbolStyle: AnyShapeStyle {
        if isHidden {
            return AnyShapeStyle(Color.white.opacity(0.7))
        }
        if tier == .obsidian {
            return AnyShapeStyle(Theme.legendaryGradient)
        }
        return AnyShapeStyle(LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .top, endPoint: .bottom))
    }

    private func startRimAnimationIfNeeded() {
        guard isUnlocked, tier == .obsidian, rimRotation == 0 else { return }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rimRotation = 360
        }
    }
}

/// Small gradient capsule naming a badge tier.
struct TierLabel: View {
    let tier: AwardTier
    var fontSize: CGFloat = 9

    var body: some View {
        Text(tier.title.uppercased())
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(Theme.horizontal(tier.labelColors))
            .padding(.horizontal, fontSize * 0.7)
            .padding(.vertical, fontSize * 0.25)
            .background(Capsule().fill(tier.glowColor.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tier.glowColor.opacity(0.3), lineWidth: 0.5))
    }
}

#Preview("Medallions") {
    ScrollView {
        VStack(spacing: 28) {
            ForEach(AwardTier.allCases) { tier in
                HStack(spacing: 22) {
                    BadgeMedallionView(iconName: "flame.fill", category: .consistency, tier: tier, size: 76)
                    BadgeMedallionView(iconName: "flame.fill", category: .consistency, tier: tier, isUnlocked: false, size: 76)
                    BadgeMedallionView(iconName: "moon.zzz.fill", category: .secret, tier: tier, isUnlocked: false, isSecret: true, size: 76)
                }
                TierLabel(tier: tier, fontSize: 11)
            }
        }
        .padding(30)
    }
    .themedScreen()
    .preferredColorScheme(.dark)
}
