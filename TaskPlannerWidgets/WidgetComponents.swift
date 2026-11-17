import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Background

/// Obsidian gradient (#090A0F → #121521) with a soft indigo glow, matching the app.
struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.indigo.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Theme.emerald.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 200
            )
        }
    }
}

// MARK: - Progress

struct WidgetProgressRing<Center: View>: View {
    let progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(colors: [Theme.indigo, Theme.violet, Theme.emerald, Theme.indigo], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.violet.opacity(0.5), radius: 4)
            center
        }
        .frame(width: size, height: size)
    }
}

struct WidgetProgressBar: View {
    let progress: Double
    var colors: [Color] = Theme.primaryColors
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Theme.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.horizontal(colors))
                        .frame(width: max(height, proxy.size.width * min(1, max(0, progress))))
                }
            }
            .clipShape(Capsule())
    }
}

// MARK: - Pills

struct WidgetStatPill: View {
    let icon: String
    let text: String
    var colors: [Color] = Theme.legendaryColors

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(Theme.diagonal(colors))
            Text(text)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(Theme.rounded(.caption2, weight: .bold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.chipBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
        .lineLimit(1)
        .fixedSize()
    }
}

struct WidgetXPPill: View {
    let effort: EffortLevel

    var body: some View {
        Text("\(effort.points) XP")
            .font(Theme.rounded(.caption2, weight: .bold))
            .foregroundStyle(effort.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(effort.tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(effort.tint.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
    }
}

// MARK: - Task row

/// Interactive checkbox: completes the task in place through `ToggleTaskCompletionIntent`.
struct WidgetCheckButton: View {
    let task: WidgetTask
    var size: CGFloat = 20

    var body: some View {
        Button(intent: ToggleTaskCompletionIntent(taskID: task.id)) {
            Circle()
                .strokeBorder(task.effort.tint, lineWidth: 2)
                .background(Circle().fill(task.effort.tint.opacity(0.12)))
                .frame(width: size, height: size)
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(task.title)")
    }
}

struct WidgetTaskRow: View {
    let task: WidgetTask
    var showsXP = true
    var font: Font = .footnote.weight(.semibold)

    var body: some View {
        HStack(spacing: 6) {
            WidgetCheckButton(task: task)
            if !showsXP {
                Circle()
                    .fill(task.effort.tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: task.effort.tint.opacity(0.7), radius: 3)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(font)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if task.isOverdue {
                    Text("Overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.rose)
                }
            }
            Spacer(minLength: 4)
            if showsXP {
                WidgetXPPill(effort: task.effort)
            }
        }
        .invalidatableContent()
    }
}

// MARK: - States

struct WidgetAllClearView: View {
    var compact = false

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 4) {
            Image(systemName: "sparkles")
                .font(compact ? .title3 : .title)
                .foregroundStyle(Theme.successGradient)
            Text("All clear")
                .font(Theme.rounded(compact ? .subheadline : .headline, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(compact ? "Enjoy it, guilt-free." : "Everything for today is done. Enjoy your time, guilt-free.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(compact ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }
}

/// Shown when the widget can't reach the shared store (App Group not set up, or the app
/// hasn't been opened yet).
struct WidgetDisconnectedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(Theme.primaryGradient)
            Text("Open Momentum")
                .font(Theme.rounded(.subheadline, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text("to connect your planner")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small uppercase section label.
struct WidgetSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(Theme.textTertiary)
    }
}
