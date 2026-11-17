import SwiftData
import SwiftUI

// MARK: - Break timer controls

/// Start / countdown / end controls for one pass. Used on the voucher, in the wallet and on the
/// crate reveal. Timed passes start a break of at least 30 minutes (a Live Activity on iPhone);
/// untimed passes can be marked used.
struct BreakTimerControls: View {
    @Environment(TaskStore.self) private var store
    @Environment(NotificationManager.self) private var notificationManager
    let pass: ActivePass
    /// White-on-gradient styling for the voucher; themed styling elsewhere.
    var onTicket = false

    @State private var startCount = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(status: pass.status(at: context.date), now: context.date)
        }
        .sensoryFeedback(.start, trigger: startCount)
        .animation(Theme.spring, value: pass.startedAt)
        .animation(Theme.spring, value: pass.finishedAt)
    }

    @ViewBuilder
    private func content(status: ActivePass.Status, now: Date) -> some View {
        switch status {
        case .saved:
            if let minutes = pass.breakMinutes {
                VStack(spacing: 8) {
                    primaryButton("Start Break Timer · \(Self.clock(minutes * 60))", icon: "timer") {
                        startCount += 1
                        Task { await notificationManager.requestAuthorization() }
                        withAnimation(Theme.spring) { store.startBreak(pass) }
                    }
                    Text(startHint)
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                primaryButton("Mark Pass as Used", icon: "checkmark.seal.fill") {
                    withAnimation(Theme.spring) { store.finishPass(pass) }
                }
            }
        case .running(let endsAt):
            VStack(spacing: 10) {
                Text(timerInterval: now...max(endsAt, now), countsDown: true)
                    .font(Theme.rounded(size: 44, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(onTicket ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.successGradient))
                    .contentTransition(.numericText(countsDown: true))
                if let start = pass.startedAt {
                    GradientProgressBar(
                        value: 1 - endsAt.timeIntervalSince(now) / max(endsAt.timeIntervalSince(start), 1),
                        colors: Theme.successColors,
                        height: 6
                    )
                }
                Button {
                    withAnimation(Theme.spring) { store.finishPass(pass) }
                } label: {
                    Label("End Break Early", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(onTicket ? Color.white : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(onTicket ? Color.white.opacity(0.18) : Theme.chipBackground))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        case .used:
            Label(pass.isTimed ? "Break complete" : "Pass used", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onTicket ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.successGradient))
        }
    }

    private var secondary: Color { onTicket ? .white.opacity(0.75) : Theme.textSecondary }

    private var startHint: String {
        #if os(iOS)
        "Counts down on your Lock Screen and in the Dynamic Island, with an alert when it's over."
        #else
        "You'll get a notification when your break is over."
        #endif
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.rounded(.headline))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.successGradient, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
                .shadow(color: Theme.emerald.opacity(0.5), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// "30:00", "1:30:00".
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Wallet

/// "Saved Passes": passes waiting to be used, plus any break that's running right now.
struct SavedPassesSection: View {
    @Query(sort: \ActivePass.createdAt, order: .reverse) private var passes: [ActivePass]
    let onOpen: (ActivePass) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = passes.filter { $0.status(at: context.date) != .used }
            if !live.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Saved Passes", subtitle: "Your wallet. Start a timed break whenever you're ready.")
                    ForEach(live) { pass in
                        Button {
                            onOpen(pass)
                        } label: {
                            SavedPassRow(pass: pass)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SavedPassRow: View {
    @Environment(TaskStore.self) private var store
    let pass: ActivePass

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = pass.status(at: context.date)
            HStack(spacing: 14) {
                GradientIcon(systemName: pass.iconName, colors: pass.rarity.colors, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(pass.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        if pass.source == .mysteryCrate {
                            RarityTag(rarity: pass.rarity)
                        }
                    }
                    subtitle(status: status, now: context.date)
                }
                Spacer(minLength: 0)
                trailing(status: status)
            }
            .padding(14)
            .glassCard(cornerRadius: 18, tint: status == .saved ? nil : Theme.emerald)
        }
    }

    @ViewBuilder
    private func subtitle(status: ActivePass.Status, now: Date) -> some View {
        switch status {
        case .running(let endsAt):
            (Text("On break · ") + Text(timerInterval: now...max(endsAt, now), countsDown: true))
                .font(Theme.rounded(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.emerald)
        default:
            Text(pass.breakMinutes.map { "\(BreakPolicy.label(for: $0)) break · saved \(pass.createdAt.formatted(.relative(presentation: .named)))" }
                 ?? "Untimed pass · saved \(pass.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func trailing(status: ActivePass.Status) -> some View {
        switch status {
        case .saved where pass.isTimed:
            chip("Start", icon: "play.fill", colors: Theme.successColors) {
                withAnimation(Theme.spring) { store.startBreak(pass) }
            }
        case .saved:
            chip("Use", icon: "checkmark", colors: Theme.primaryColors) {
                withAnimation(Theme.spring) { store.finishPass(pass) }
            }
        case .running:
            chip("End", icon: "stop.fill", colors: [Color(hex: 0x475569), Color(hex: 0x334155)]) {
                withAnimation(Theme.spring) { store.finishPass(pass) }
            }
        case .used:
            EmptyView()
        }
    }

    private func chip(_ title: String, icon: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.diagonal(colors), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RarityTag: View {
    let rarity: PassRarity

    var body: some View {
        Text(rarity.title.uppercased())
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.diagonal(rarity.colors), in: Capsule())
    }
}
