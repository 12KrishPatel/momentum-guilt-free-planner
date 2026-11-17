import SwiftUI

/// Opens a Mystery Loot Box: deducts the points, builds suspense with a 1.2-second spring shake
/// and radial glow (with haptics), then reveals the won Guilt-Free Pass with rarity styling.
/// The pass is already in the Saved Passes wallet by the time it's revealed.
struct CrateOpeningModal: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let crate: MysteryCrate

    private enum Phase: Equatable {
        case ready
        case opening
        case revealed
        case unaffordable
    }

    @State private var phase: Phase = .ready
    @State private var result: TaskStore.CrateResult?
    @State private var shakeAngle: Double = 0
    @State private var crateScale: CGFloat = 1
    @State private var glow: Double = 0
    @State private var hapticTick = 0
    @State private var revealCount = 0
    @State private var revealScale: CGFloat = 0.4
    @State private var flash: Double = 0

    private var balance: Int { store.currentBalance() }

    var body: some View {
        NavigationStack {
            ZStack {
                radialGlow
                VStack(spacing: 22) {
                    Spacer(minLength: 8)
                    switch phase {
                    case .ready, .opening, .unaffordable:
                        crateStage
                    case .revealed:
                        if let result { revealStage(result) }
                    }
                    Spacer(minLength: 8)
                }
                .padding(24)

                Color.white.opacity(flash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .opening {
                        Button(phase == .revealed ? "Done" : "Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .opening)
        .presentationBackground(Theme.obsidianTop)
        .macSheetFrame(width: 460, height: 680)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: hapticTick)
        .sensoryFeedback(trigger: revealCount) { _, _ in
            (result?.drop.rarity ?? .common) >= .epic ? .success : .impact(weight: .heavy)
        }
    }

    // MARK: Crate

    private var crateStage: some View {
        VStack(spacing: 22) {
            CrateArt(crate: crate, size: 150, glow: 0.4 + glow * 0.6)
                .rotationEffect(.degrees(shakeAngle))
                .scaleEffect(crateScale)

            VStack(spacing: 6) {
                Text(crate.title)
                    .font(Theme.rounded(.title2, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(phase == .opening ? "Opening…" : crate.tagline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if phase == .unaffordable {
                Text("You need \(crate.cost) Leisure Points. Finish a task or two and come back.")
                    .font(.footnote)
                    .foregroundStyle(Theme.rose)
                    .multilineTextAlignment(.center)
            }

            if phase != .opening {
                Button(action: open) {
                    Label("Open for \(crate.cost) pts", systemImage: "sparkles")
                        .font(Theme.rounded(.headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.diagonal(crate.colors), in: Capsule())
                        .shadow(color: (crate.colors.last ?? Theme.rose).opacity(0.55), radius: 14, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(balance < crate.cost)
                .opacity(balance < crate.cost ? 0.45 : 1)

                Text("Balance: \(balance) pts")
                    .font(Theme.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Reveal

    private func revealStage(_ result: TaskStore.CrateResult) -> some View {
        let rarity = result.drop.rarity
        return VStack(spacing: 18) {
            Text(rarity >= .legendary ? "LEGENDARY DROP!" : "\(rarity.title.uppercased()) DROP")
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(Theme.diagonal(rarity.colors))

            VStack(spacing: 14) {
                GradientIcon(systemName: result.drop.iconName, colors: [.white.opacity(0.35), .white.opacity(0.12)], size: 84)
                Text(result.drop.title)
                    .font(Theme.rounded(.title2, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.drop.details)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RarityTag(rarity: rarity)
                    if let minutes = result.drop.breakMinutes {
                        Text(BreakPolicy.label(for: minutes))
                            .font(Theme.rounded(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.diagonal(rarity.colors), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: rarity.glowColor.opacity(0.6), radius: 30, y: 12)
            .scaleEffect(revealScale)

            Label("Saved to your wallet", systemImage: "wallet.pass.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            BreakTimerControls(pass: result.pass)
        }
    }

    // MARK: Glow

    private var radialGlow: some View {
        let color = phase == .revealed ? (result?.drop.rarity.glowColor ?? Theme.rose) : (crate.colors.last ?? Theme.rose)
        return RadialGradient(
            colors: [color.opacity(0.15 + glow * 0.55), color.opacity(0)],
            center: .center,
            startRadius: 10,
            endRadius: 120 + glow * 320
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Actions

    private func open() {
        guard let opened = store.openCrate(crate) else {
            withAnimation(Theme.spring) { phase = .unaffordable }
            return
        }
        result = opened
        phase = .opening

        Task {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.6)) { glow = 1 }
                try? await Task.sleep(for: .milliseconds(600))
            } else {
                // 8 spring kicks of growing amplitude over 1.2 s while the glow builds.
                let steps = 8
                for step in 0..<steps {
                    let amplitude = 4 + Double(step) * 1.6
                    withAnimation(.spring(response: 0.11, dampingFraction: 0.32)) {
                        shakeAngle = step.isMultiple(of: 2) ? amplitude : -amplitude
                        crateScale = 1 + CGFloat(step) * 0.018
                    }
                    withAnimation(.easeIn(duration: 0.15)) {
                        glow = Double(step + 1) / Double(steps)
                    }
                    hapticTick += 1
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            withAnimation(.easeOut(duration: 0.12)) { flash = 0.55 }
            try? await Task.sleep(for: .milliseconds(120))
            phase = .revealed
            revealCount += 1
            shakeAngle = 0
            withAnimation(.easeOut(duration: 0.45)) { flash = 0 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { revealScale = 1 }
            withAnimation(.easeOut(duration: 1.2)) { glow = 0.6 }
        }
    }
}

#Preview("Crate opening") {
    CrateOpeningModal(crate: .obsidianJackpot)
        .previewEnvironment()
}
