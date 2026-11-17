import SwiftData
import SwiftUI

/// "Leisure Rewards" half of the Awards tab: balance, daily checkpoints, shop and pass history.
/// Lays out as plain content so it can sit inside the parent ScrollView.
struct RewardsView: View {
    @Environment(TaskStore.self) private var store
    @Query(sort: \RewardCheckpoint.cost) private var rewards: [RewardCheckpoint]
    @Query(sort: \RewardRedemption.redeemedAt, order: .reverse) private var redemptions: [RewardRedemption]
    @Query private var tasks: [TaskItem]

    @State private var pendingRedemption: RewardCheckpoint?
    @State private var presentedPass: RewardRedemption?
    @State private var isAddingReward = false
    @State private var rewardToDelete: RewardCheckpoint?

    private var lifetimeXP: Int { PlannerStats.totalXP(tasks) }
    private var spent: Int { RewardMath.pointsSpent(redemptions) }
    private var balance: Int { RewardMath.balance(tasks: tasks, redemptions: redemptions) }
    private var todayXP: Int { PlannerStats.xpEarned(on: .now, tasks: tasks) }
    private var dailies: [RewardCheckpoint] { rewards.filter { $0.kind == .dailyCheckpoint } }
    private var shop: [RewardCheckpoint] {
        rewards
            .filter { $0.kind == .shopReward }
            .sorted { $0.cost == $1.cost ? $0.sortOrder < $1.sortOrder : $0.cost < $1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            LeisureBalanceCard(balance: balance, lifetimeXP: lifetimeXP, spent: spent, todayXP: todayXP)

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Today's Checkpoints", subtitle: "Hit today's XP targets to unlock free breaks. Resets daily.")
                ForEach(dailies) { checkpoint in
                    DailyCheckpointCard(
                        checkpoint: checkpoint,
                        todayXP: todayXP,
                        isClaimed: RewardMath.isClaimed(checkpoint, redemptions: redemptions)
                    ) {
                        if let pass = store.claimDailyCheckpoint(checkpoint) {
                            presentedPass = pass
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SectionTitle("Rewards Shop", subtitle: "Spend Leisure Points on real-world treats.")
                    Spacer()
                    Button {
                        isAddingReward = true
                    } label: {
                        Label("Custom", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.primaryGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(shop) { reward in
                    RewardShopCard(reward: reward, balance: balance) {
                        pendingRedemption = reward
                    }
                    .contextMenu {
                        Button {
                            pendingRedemption = reward
                        } label: {
                            Label("Redeem", systemImage: "ticket.fill")
                        }
                        .disabled(balance < reward.cost)

                        if reward.isCustom {
                            Button(role: .destructive) {
                                rewardToDelete = reward
                            } label: {
                                Label("Delete Reward", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !redemptions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Your Guilt-Free Passes", subtitle: "Tap a pass to view it again.")
                    VStack(spacing: 0) {
                        ForEach(Array(redemptions.prefix(8))) { redemption in
                            Button {
                                presentedPass = redemption
                            } label: {
                                PassHistoryRow(redemption: redemption)
                            }
                            .buttonStyle(.plain)
                            if redemption.id != redemptions.prefix(8).last?.id {
                                Divider().overlay(Theme.separator).padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .glassCard(cornerRadius: 18)
                }
            }
        }
        .sheet(item: $presentedPass) { pass in
            GuiltFreePassView(redemption: pass)
        }
        .sheet(isPresented: $isAddingReward) {
            AddRewardSheet()
        }
        .confirmationDialog(
            "Claim this reward?",
            isPresented: Binding(
                get: { pendingRedemption != nil },
                set: { if !$0 { pendingRedemption = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRedemption
        ) { reward in
            Button("Spend \(reward.cost) pts") {
                if let pass = store.redeem(reward) {
                    presentedPass = pass
                }
            }
        } message: { reward in
            Text("Redeem “\(reward.title)” for \(reward.cost) Leisure Points and get your Guilt-Free Pass.")
        }
        .confirmationDialog(
            "Delete this custom reward?",
            isPresented: Binding(
                get: { rewardToDelete != nil },
                set: { if !$0 { rewardToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: rewardToDelete
        ) { reward in
            Button("Delete “\(reward.title)”", role: .destructive) {
                withAnimation(Theme.spring) { store.deleteReward(reward) }
            }
        } message: { _ in
            Text("Passes you've already claimed for it are kept.")
        }
    }
}

// MARK: - Balance

struct LeisureBalanceCard: View {
    let balance: Int
    let lifetimeXP: Int
    let spent: Int
    let todayXP: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEISURE POINTS")
                        .font(.caption.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(balance)")
                        .font(Theme.rounded(size: 48, weight: .heavy))
                        .foregroundStyle(Theme.successGradient)
                        .contentTransition(.numericText(value: Double(balance)))
                        .shadow(color: Theme.emerald.opacity(0.35), radius: 12)
                }
                Spacer()
                GradientIcon(systemName: "leaf.fill", colors: Theme.successColors, size: 54)
            }

            HStack(spacing: 8) {
                metric(title: "Lifetime XP", value: lifetimeXP)
                metric(title: "Spent", value: spent)
                metric(title: "Today", value: todayXP)
            }

            Text("Every task earns points 1:1 with its XP—Quick 10, Standard 25, Deep Work 50.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(18)
        .glassCard(tint: Theme.emerald)
        .animation(Theme.spring, value: balance)
        .accessibilityElement(children: .combine)
    }

    private func metric(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Theme.rounded(.headline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(value)))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Daily checkpoint

struct DailyCheckpointCard: View {
    let checkpoint: RewardCheckpoint
    let todayXP: Int
    let isClaimed: Bool
    let onClaim: () -> Void

    private var isReached: Bool { todayXP >= checkpoint.cost }

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(systemName: checkpoint.iconName, colors: Theme.successColors, size: 44, isActive: isReached)

            VStack(alignment: .leading, spacing: 6) {
                Text(checkpoint.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(checkpoint.details)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                GradientProgressBar(
                    value: Double(todayXP) / Double(max(checkpoint.cost, 1)),
                    colors: Theme.successColors,
                    height: 5
                )
                Text("\(min(todayXP, checkpoint.cost)) / \(checkpoint.cost) XP today")
                    .font(Theme.rounded(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(14)
        .glassCard(cornerRadius: 18, tint: isReached && !isClaimed ? Theme.emerald : nil)
        .animation(Theme.spring, value: isReached)
        .animation(Theme.spring, value: isClaimed)
    }

    @ViewBuilder
    private var trailing: some View {
        if isClaimed {
            Label("Claimed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(Theme.successGradient)
                .accessibilityLabel("Claimed today")
        } else if isReached {
            Button(action: onClaim) {
                Text("Claim")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.successGradient, in: Capsule())
                    .shadow(color: Theme.emerald.opacity(0.5), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityLabel("Locked")
        }
    }
}

// MARK: - Shop card

struct RewardShopCard: View {
    let reward: RewardCheckpoint
    let balance: Int
    let onRedeem: () -> Void

    private var canAfford: Bool { balance >= reward.cost }

    private var colors: [Color] {
        switch reward.cost {
        case 300...: Theme.legendaryColors
        case 100..<300: Theme.primaryColors
        default: Theme.successColors
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(systemName: reward.iconName, colors: colors, size: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reward.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if reward.isCustom {
                        Text("CUSTOM")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.violet.opacity(0.15), in: Capsule())
                    }
                }
                if !reward.details.isEmpty {
                    Text(reward.details)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                if !canAfford {
                    GradientProgressBar(value: Double(balance) / Double(max(reward.cost, 1)), colors: colors, height: 4)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(reward.cost) pts")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(Theme.diagonal(colors))
                Button(action: onRedeem) {
                    Text(canAfford ? "Redeem" : "\(reward.cost - balance) more")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(canAfford ? Color.white : Theme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if canAfford {
                                Capsule().fill(Theme.diagonal(colors))
                            } else {
                                Capsule().fill(Theme.chipBackground)
                            }
                        }
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .animation(Theme.spring, value: canAfford)
    }
}

// MARK: - Pass history

struct PassHistoryRow: View {
    let redemption: RewardRedemption

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(
                systemName: redemption.iconName,
                colors: redemption.kind == .dailyCheckpoint ? Theme.successColors : Theme.primaryColors,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(redemption.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(redemption.redeemedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(redemption.pointsSpent > 0 ? "−\(redemption.pointsSpent)" : "FREE")
                .font(Theme.rounded(.footnote))
                .foregroundStyle(redemption.pointsSpent > 0 ? Theme.textSecondary : Theme.emerald)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Custom reward sheet

struct AddRewardSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var cost = 100
    @State private var iconName = RewardCatalog.customIcons[0]
    @FocusState private var isTitleFocused: Bool

    private let presets = [25, 50, 100, 250, 500]
    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cost > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GradientIcon(systemName: iconName, colors: Theme.primaryColors, size: 48)
                            .contentTransition(.symbolEffect(.replace))
                        TextField("Reward name", text: $title)
                            .font(.headline)
                            .focused($isTitleFocused)
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                .glassRow()

                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(RewardCatalog.customIcons, id: \.self) { icon in
                            let isSelected = icon == iconName
                            Button {
                                withAnimation(Theme.spring) { iconName = icon }
                            } label: {
                                Image(systemName: icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                                    .frame(width: 42, height: 42)
                                    .background {
                                        if isSelected {
                                            Circle().fill(Theme.primaryGradient)
                                        } else {
                                            Circle().fill(Theme.chipBackground)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
                .glassRow()

                Section {
                    Stepper(value: $cost, in: 5...5000, step: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(cost)")
                                .font(Theme.rounded(.title2))
                                .foregroundStyle(Theme.primaryGradient)
                                .contentTransition(.numericText(value: Double(cost)))
                            Text("points")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                withAnimation(Theme.spring) { cost = preset }
                            } label: {
                                Text("\(preset)")
                                    .font(Theme.rounded(.footnote, weight: .semibold))
                                    .foregroundStyle(cost == preset ? Color.white : Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background {
                                        if cost == preset {
                                            Capsule().fill(Theme.primaryGradient)
                                        } else {
                                            Capsule().fill(Theme.chipBackground)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Point Cost")
                } footer: {
                    Text("For scale: a Standard task earns 25 points, a Deep Work task 50.")
                }
                .glassRow()
            }
            .themedScreen()
            .navigationTitle("Custom Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addCustomReward(title: title, details: notes, iconName: iconName, cost: cost)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .sensoryFeedback(.selection, trigger: iconName)
            .sensoryFeedback(.selection, trigger: cost)
            .onAppear { isTitleFocused = true }
        }
    }
}

#Preview("Rewards") {
    ScrollView {
        RewardsView()
            .padding()
    }
    .themedScreen()
    .previewEnvironment()
}

#Preview("Custom reward") {
    AddRewardSheet()
        .previewEnvironment()
}
