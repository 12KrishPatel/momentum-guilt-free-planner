import SwiftUI

// MARK: - Combo badge pill

/// Glowing amber-to-rose pill, e.g. "1.5x COMBO · 38m left", shown while a multiplier is active.
struct ComboBadgePill: View {
    let status: ComboStatus

    @State private var glow = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 6) {
                Image(systemName: status.kind == .earlyFinisher ? "sunrise.fill" : "bolt.fill")
                    .font(.caption.weight(.heavy))
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(status.multiplierText) \(status.kind?.title ?? "COMBO")")
                    .font(Theme.rounded(.caption, weight: .heavy))
                    .tracking(0.6)
                if let left = timeLeft(at: context.date) {
                    Text("· \(left)")
                        .font(Theme.rounded(.caption, weight: .semibold))
                        .opacity(0.85)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.legendaryGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
            // Kept tight so the glow fits inside list-row padding (rows clip their content).
            .shadow(color: Theme.rose.opacity(glow ? 0.85 : 0.45), radius: glow ? 6 : 3)
            .shadow(color: Theme.amber.opacity(glow ? 0.4 : 0.15), radius: glow ? 7 : 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func timeLeft(at now: Date) -> String? {
        guard let expiresAt = status.expiresAt else { return nil }
        let minutes = Int((expiresAt.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return nil }
        if status.kind == .earlyFinisher { return "all day" }
        return "\(minutes)m left"
    }

    private var accessibilityText: String {
        switch status.kind {
        case .earlyFinisher: "Early Finisher bonus: \(status.multiplierText) XP for the rest of today"
        case .overdrive: "Overdrive: \(status.multiplierText) XP on your next task"
        default: "Momentum combo: \(status.multiplierText) XP. Finish another task to reach Overdrive."
        }
    }
}

/// Shows the pill only while a multiplier is active.
struct ComboBadgeSlot: View {
    @Environment(ComboEngine.self) private var combo: ComboEngine?

    var body: some View {
        if let combo, combo.activeMultiplier > 1 {
            ComboBadgePill(status: combo.status)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

// MARK: - Floating +XP

private struct XPBurst: Identifiable {
    let id: UUID
    let text: String
    let isBoosted: Bool
}

/// Floats a "+38 XP · 1.5x" pill up and away whenever a task is checked off.
private struct XPBurstOverlay: ViewModifier {
    @Environment(ComboEngine.self) private var combo: ComboEngine?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [XPBurst] = []
    @State private var risen: Set<UUID> = []

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    ForEach(bursts) { burst in
                        pill(burst)
                            .offset(y: risen.contains(burst.id) ? (reduceMotion ? 0 : -46) : 0)
                            .opacity(risen.contains(burst.id) ? 0 : 1)
                            .scaleEffect(risen.contains(burst.id) ? 1.08 : 0.9)
                    }
                }
                .offset(y: -40)
                .allowsHitTesting(false)
            }
            .onChange(of: combo?.lastReward?.id) { _, _ in
                guard let reward = combo?.lastReward else { return }
                show(reward)
            }
    }

    private func pill(_ burst: XPBurst) -> some View {
        Text(burst.text)
            .font(Theme.rounded(.subheadline, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(burst.isBoosted ? Theme.legendaryGradient : Theme.primaryGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
            .shadow(color: (burst.isBoosted ? Theme.rose : Theme.violet).opacity(0.6), radius: 12, y: 4)
    }

    private func show(_ reward: CompletionReward) {
        let text = reward.multiplier > 1
            ? "+\(reward.xp) XP · \(ComboMath.format(reward.multiplier))"
            : "+\(reward.xp) XP"
        let burst = XPBurst(id: reward.id, text: text, isBoosted: reward.multiplier > 1)
        bursts.append(burst)
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeOut(duration: 1.0)) { _ = risen.insert(burst.id) }
            try? await Task.sleep(for: .milliseconds(1100))
            bursts.removeAll { $0.id == burst.id }
            risen.remove(burst.id)
        }
    }
}

extension View {
    /// Adds the floating "+XP" pill shown when a task is checked off.
    func xpBurstOverlay() -> some View {
        modifier(XPBurstOverlay())
    }
}

#Preview("Combo pills") {
    VStack(spacing: 14) {
        ComboBadgePill(status: ComboStatus(multiplier: 1.5, kind: .momentum, chainCount: 2, expiresAt: .now.addingTimeInterval(38 * 60)))
        ComboBadgePill(status: ComboStatus(multiplier: 2, kind: .overdrive, chainCount: 3, expiresAt: .now.addingTimeInterval(21 * 60)))
        ComboBadgePill(status: ComboStatus(multiplier: 1.5, kind: .earlyFinisher, chainCount: 0, expiresAt: .now.addingTimeInterval(5 * 3600)))
    }
    .padding()
    .themedScreen()
    .preferredColorScheme(.dark)
}
