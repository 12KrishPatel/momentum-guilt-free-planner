import SwiftUI

/// "Mystery Loot Boxes": the two purchasable crates at the top of Leisure Rewards.
struct MysteryVaultView: View {
    let balance: Int
    let onOpen: (MysteryCrate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Mystery Loot Boxes", subtitle: "Spend points on a surprise break. Every timed drop is 30+ minutes.")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    cards
                }
                VStack(spacing: 12) {
                    cards
                }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(MysteryCrate.all) { crate in
            MysteryCrateCard(crate: crate, balance: balance) { onOpen(crate) }
                .frame(minWidth: 320)
        }
    }
}

struct MysteryCrateCard: View {
    let crate: MysteryCrate
    let balance: Int
    let onOpen: () -> Void

    @State private var float = false
    private var canAfford: Bool { balance >= crate.cost }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CrateArt(crate: crate, size: 58, glow: canAfford ? 0.55 : 0.15)
                    .offset(y: float ? -2 : 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(crate.title)
                        .font(Theme.rounded(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text(crate.tagline)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Odds, published up front.
            VStack(spacing: 5) {
                ForEach(crate.drops) { drop in
                    HStack(spacing: 8) {
                        Circle().fill(Theme.diagonal(drop.rarity.colors)).frame(width: 7, height: 7)
                        Text(drop.title)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Text("\(drop.weight)%")
                            .font(Theme.rounded(.caption, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: canAfford ? "sparkles" : "lock.fill")
                    Text(canAfford ? "Open · \(crate.cost) pts" : "\(crate.cost - balance) more pts")
                }
                .font(Theme.rounded(.subheadline))
                .foregroundStyle(canAfford ? Color.white : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    if canAfford {
                        Capsule().fill(Theme.diagonal(crate.colors))
                    } else {
                        Capsule().fill(Theme.chipBackground)
                    }
                }
                .shadow(color: canAfford ? (crate.colors.last ?? Theme.rose).opacity(0.5) : .clear, radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
        .padding(16)
        .glassCard(cornerRadius: 20, tint: canAfford ? crate.colors.last : nil)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The crate "object": a gradient tile with the crate symbol and a soft glow.
struct CrateArt: View {
    let crate: MysteryCrate
    var size: CGFloat = 58
    var glow: Double = 0.5

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Theme.diagonal(crate.colors))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(
                Image(systemName: crate.iconName)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: (crate.colors.last ?? Theme.rose).opacity(glow), radius: size * 0.3)
            .accessibilityHidden(true)
    }
}

#Preview("Mystery Vault") {
    ScrollView {
        MysteryVaultView(balance: 80) { _ in }
            .padding()
    }
    .themedScreen()
    .preferredColorScheme(.dark)
}
