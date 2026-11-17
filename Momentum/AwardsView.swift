import SwiftData
import SwiftUI

enum TrophyTab: String, CaseIterable, Identifiable {
    case badges
    case rewards

    var id: String { rawValue }
}

struct AwardsView: View {
    @Query private var awards: [Award]
    @Query private var tasks: [TaskItem]
    @State private var tab: TrophyTab
    @State private var selectedAward: Award?

    /// When set (the macOS sidebar), shows only this section and hides the switcher.
    private let fixedTab: TrophyTab?

    init(fixedTab: TrophyTab? = nil) {
        self.fixedTab = fixedTab
        _tab = State(initialValue: fixedTab ?? .badges)
    }

    private var currentTab: TrophyTab { fixedTab ?? tab }

    private var title: String {
        switch fixedTab {
        case .badges: "Trophy Case"
        case .rewards: "Leisure Rewards"
        case nil: "Awards"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if fixedTab == nil {
                        Picker("Section", selection: $tab) {
                            Text("Badges (\(awards.count))").tag(TrophyTab.badges)
                            Text("Leisure Rewards").tag(TrophyTab.rewards)
                        }
                        .pickerStyle(.segmented)
                    }

                    switch currentTab {
                    case .badges:
                        BadgeCollectionView(
                            awards: awards,
                            streak: PlannerStats.currentStreak(tasks)
                        ) { award in
                            selectedAward = award
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .rewards:
                        RewardsView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(Platform.isMac ? 24 : 16)
                .frame(maxWidth: Platform.isMac ? 980 : .infinity)
                .frame(maxWidth: .infinity)
                .animation(Theme.spring, value: tab)
            }
            .themedScreen()
            .navigationTitle(title)
            .sheet(item: $selectedAward) { award in
                AwardDetailSheet(award: award)
            }
            .sensoryFeedback(.selection, trigger: tab)
            .sensoryFeedback(.selection, trigger: selectedAward?.id)
        }
    }
}

// MARK: - Badge collection

struct BadgeCollectionView: View {
    let awards: [Award]
    let streak: Int
    let onSelect: (Award) -> Void

    /// When set, only badges of this tier are shown.
    @State private var tierFilter: AwardTier?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private func awards(in category: AwardCategory) -> [Award] {
        awards
            .filter { $0.category == category && (tierFilter == nil || $0.tier == tierFilter) }
            .sorted { (AwardEngine.catalogOrder[$0.id] ?? .max) < (AwardEngine.catalogOrder[$1.id] ?? .max) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            AwardsSummaryHeader(awards: awards, streak: streak, selectedTier: $tierFilter)

            if let tierFilter {
                TierFilterBanner(
                    tier: tierFilter,
                    count: awards.count { $0.tier == tierFilter }
                ) {
                    withAnimation(Theme.spring) { self.tierFilter = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ForEach(AwardCategory.allCases) { category in
                let items = awards(in: category)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CategoryHeader(
                            category: category,
                            unlocked: items.count(where: \.isUnlocked),
                            total: items.count
                        )
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { award in
                                Button {
                                    onSelect(award)
                                } label: {
                                    BadgeCard(award: award)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .animation(Theme.spring, value: tierFilter)
        .sensoryFeedback(.selection, trigger: tierFilter)
    }
}

/// Shown above the grid while a tier filter is active.
private struct TierFilterBanner: View {
    let tier: AwardTier
    let count: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.horizontal(tier.labelColors))
            Text("Showing \(count) ")
                .foregroundStyle(Theme.textSecondary)
            + Text(tier.title)
                .foregroundStyle(Theme.horizontal(tier.labelColors))
                .fontWeight(.bold)
            + Text(count == 1 ? " badge" : " badges")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Show all", action: onClear)
                .font(.subheadline.weight(.semibold))
                .tint(Theme.violet)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, tint: tier.glowColor)
    }
}

private struct CategoryHeader: View {
    let category: AwardCategory
    let unlocked: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(category.gradient)
            Text(category.title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(unlocked)/\(total)")
                .font(Theme.rounded(.subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText(value: Double(unlocked)))
        }
    }
}

// MARK: - Summary header

struct AwardsSummaryHeader: View {
    let awards: [Award]
    let streak: Int
    @Binding var selectedTier: AwardTier?

    private var unlocked: Int { awards.count(where: \.isUnlocked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                BadgeMedallionView(iconName: "trophy.fill", category: .volume, tier: .gold, size: 64)
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(unlocked)")
                            .font(Theme.rounded(size: 34, weight: .heavy))
                            .foregroundStyle(Theme.primaryGradient)
                            .contentTransition(.numericText(value: Double(unlocked)))
                        Text("/ \(awards.count) Unlocked")
                            .font(Theme.rounded(.headline, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    GradientProgressBar(value: Double(unlocked) / Double(max(awards.count, 1)), height: 8)

                    Label(
                        streak == 0 ? "No active streak—complete a task today" : "\(streak)-day active streak",
                        systemImage: "flame.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(streak == 0 ? Theme.textSecondary : Theme.amber)
                }
            }

            HStack(spacing: 8) {
                ForEach(AwardTier.allCases) { tier in
                    let inTier = awards.filter { $0.tier == tier }
                    TierFilterChip(
                        tier: tier,
                        unlocked: inTier.count(where: \.isUnlocked),
                        total: inTier.count,
                        isSelected: selectedTier == tier,
                        isDimmed: selectedTier != nil && selectedTier != tier
                    ) {
                        withAnimation(Theme.spring) {
                            selectedTier = selectedTier == tier ? nil : tier
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
        .accessibilityElement(children: .contain)
    }
}

/// Tier count chip that toggles the badge grid's tier filter.
private struct TierFilterChip: View {
    let tier: AwardTier
    let unlocked: Int
    let total: Int
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                TierLabel(tier: tier)
                Text("\(unlocked)/\(total)")
                    .font(Theme.rounded(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(unlocked)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                shape.fill(isSelected ? tier.glowColor.opacity(0.22) : Theme.chipBackground)
            }
            .overlay {
                shape.strokeBorder(
                    isSelected ? AnyShapeStyle(Theme.diagonal(tier.labelColors)) : AnyShapeStyle(Color.clear),
                    lineWidth: 1.5
                )
            }
            .shadow(color: isSelected ? tier.glowColor.opacity(0.45) : .clear, radius: 8)
            .scaleEffect(isSelected ? 1.04 : 1)
            .opacity(isDimmed ? 0.45 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.title) badges, \(unlocked) of \(total) unlocked")
        .accessibilityHint(isSelected ? "Double tap to show all badges" : "Double tap to show only \(tier.title) badges")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Grid card

struct BadgeCard: View {
    let award: Award

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 8) {
            BadgeMedallionView(
                iconName: award.iconName,
                category: award.category,
                tier: award.tier,
                isUnlocked: award.isUnlocked,
                isSecret: award.isSecret,
                size: 58
            )
            .padding(.top, 4)

            Text(award.isHidden ? "???" : award.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(award.isUnlocked ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TierLabel(tier: award.tier)

            footer
                .frame(height: 12)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18)
        .overlay {
            if award.isUnlocked, award.tier >= .gold {
                shape.strokeBorder(Theme.diagonal(award.tier.labelColors).opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(award.isHidden ? "Secret badge" : "\(award.title), \(award.tier.title)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var footer: some View {
        if award.isUnlocked {
            Text(award.unlockedDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Unlocked")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.successGradient)
        } else if award.isHidden {
            Text("Hidden")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        } else {
            GradientProgressBar(value: award.progressFraction, colors: award.tier.labelColors, height: 4)
                .padding(.horizontal, 6)
        }
    }

    private var accessibilityValue: String {
        if award.isUnlocked { return "Unlocked" }
        if award.isHidden { return "Locked" }
        return "Locked, \(award.currentProgress) of \(award.targetProgress)"
    }
}

// MARK: - Detail sheet

struct AwardDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let award: Award

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BadgeMedallionView(
                        iconName: award.iconName,
                        category: award.category,
                        tier: award.tier,
                        isUnlocked: award.isUnlocked,
                        isSecret: award.isSecret,
                        size: 124
                    )
                    .frame(height: 170)

                    VStack(spacing: 10) {
                        Text(award.isHidden ? "???" : award.title)
                            .font(Theme.rounded(.title))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 8) {
                            TierLabel(tier: award.tier, fontSize: 11)
                            Label(award.category.title, systemImage: award.category.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(award.category.gradient)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.chipBackground, in: Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        if award.isHidden {
                            detailBlock(
                                title: "Secret Milestone",
                                icon: "eye.slash.fill",
                                text: "This badge stays hidden until you discover it. Keep planning and completing tasks—you'll know it when you see it."
                            )
                        } else {
                            detailBlock(title: "How to earn it", icon: "target", text: award.details)
                            if let tip = AwardEngine.definition(for: award.id)?.tip {
                                detailBlock(title: "Tip", icon: "lightbulb.fill", text: tip)
                            }
                        }

                        if award.isUnlocked {
                            detailBlock(
                                title: "Unlocked",
                                icon: "checkmark.seal.fill",
                                text: award.unlockedDate?.formatted(date: .long, time: .shortened) ?? "Earned"
                            )
                        } else if !award.isHidden {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                GradientProgressBar(value: award.progressFraction, colors: award.tier.labelColors)
                                Text("\(award.currentProgress) of \(award.targetProgress)")
                                    .font(Theme.rounded(.footnote, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 20)
                }
                .padding(20)
            }
            .themedScreen()
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.obsidianBottom)
        .macSheetFrame(width: 440, height: 620)
    }

    private func detailBlock(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Unlock celebration

/// Full-screen overlay shown when an award transitions from locked to unlocked.
struct AwardUnlockedBanner: View {
    let unlock: AwardUnlock
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var sparklesOut = false

    private var accentColors: [Color] {
        unlock.tier == .obsidian ? Theme.legendaryColors : unlock.tier.labelColors
    }

    private var headline: String {
        if unlock.isSecret { return "SECRET BADGE DISCOVERED" }
        if unlock.tier == .obsidian { return "LEGENDARY UNLOCKED" }
        return "\(unlock.tier.title.uppercased()) BADGE UNLOCKED"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                Text(headline)
                    .font(.caption.weight(.heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.horizontal(accentColors))

                ZStack {
                    ForEach(0..<12, id: \.self) { index in
                        let angle = Double(index) / 12 * 2 * .pi
                        Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                            .font(.system(size: index.isMultiple(of: 2) ? 16 : 10, weight: .bold))
                            .foregroundStyle(accentColors[index % accentColors.count])
                            .offset(
                                x: cos(angle) * (sparklesOut ? 112 : 20),
                                y: sin(angle) * (sparklesOut ? 112 : 20)
                            )
                            .opacity(sparklesOut ? 1 : 0)
                            .scaleEffect(sparklesOut ? 1 : 0.2)
                    }

                    BadgeMedallionView(
                        iconName: unlock.iconName,
                        category: unlock.category,
                        tier: unlock.tier,
                        isSecret: unlock.isSecret,
                        size: 136
                    )
                    .scaleEffect(hasAppeared ? 1 : 0.15)
                    .rotationEffect(.degrees(hasAppeared ? 0 : -40))
                }
                .frame(height: 230)

                VStack(spacing: 8) {
                    Text(unlock.title)
                        .font(Theme.rounded(.title))
                        .foregroundStyle(Theme.textPrimary)
                    TierLabel(tier: unlock.tier, fontSize: 11)
                    Text(unlock.details)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onDismiss) {
                    Text("Awesome!")
                        .font(Theme.rounded(.headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            unlock.tier == .obsidian ? Theme.legendaryGradient : Theme.primaryGradient,
                            in: Capsule()
                        )
                        .shadow(color: (accentColors.last ?? Theme.violet).opacity(0.5), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
            }
            .padding(26)
            .glassCard(cornerRadius: 30)
            .padding(.horizontal, 28)
            .scaleEffect(hasAppeared ? 1 : 0.85)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) {
                hasAppeared = true
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.15)) {
                sparklesOut = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Award unlocked: \(unlock.title), \(unlock.tier.title). \(unlock.details)")
    }
}

#Preview("Trophy case") {
    AwardsView()
        .previewEnvironment()
}

#Preview("Unlock banner") {
    AwardUnlockedBanner(unlock: PreviewSampleData.sampleUnlock, onDismiss: {})
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
