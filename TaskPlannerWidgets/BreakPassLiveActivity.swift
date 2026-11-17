#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Guilt-Free Pass break timer: Lock Screen / banner card and Dynamic Island.
struct BreakPassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreakPassAttributes.self) { context in
            BreakPassLockScreenView(context: context)
                .activityBackgroundTint(Theme.obsidianTop.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.emerald)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BreakPassIcon(iconName: context.state.iconName, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BreakCountdownText(endTime: context.state.endTime, isStale: context.isStale)
                        .font(Theme.rounded(.title2, weight: .heavy))
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GUILT-FREE BREAK")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.1)
                            .foregroundStyle(Theme.emerald)
                        Text(context.state.passTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        BreakProgressBar(start: context.attributes.startTime, end: context.state.endTime)
                        Button(intent: EndBreakEarlyIntent(passID: context.attributes.passID)) {
                            Label("End Early", systemImage: "stop.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.emerald)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.successGradient)
            } compactTrailing: {
                BreakCountdownText(endTime: context.state.endTime, isStale: context.isStale)
                    .font(Theme.rounded(.caption, weight: .heavy))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.emerald)
            }
            .keylineTint(Theme.emerald)
        }
    }
}

// MARK: - Lock Screen

struct BreakPassLockScreenView: View {
    let context: ActivityViewContext<BreakPassAttributes>

    var body: some View {
        HStack(spacing: 14) {
            BreakPassIcon(iconName: context.state.iconName, size: 50)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.isStale ? "BREAK COMPLETE" : "GUILT-FREE BREAK")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.successGradient)
                Text(context.state.passTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                BreakProgressBar(start: context.attributes.startTime, end: context.state.endTime)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                BreakCountdownText(endTime: context.state.endTime, isStale: context.isStale)
                    .font(Theme.rounded(size: 30, weight: .heavy))
                    .frame(maxWidth: 110, alignment: .trailing)
                if !context.isStale {
                    Button(intent: EndBreakEarlyIntent(passID: context.attributes.passID)) {
                        Text("End Early")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.emerald)
                }
            }
        }
        .padding(16)
        .background {
            // Obsidian glass with an emerald-to-teal rim.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Theme.obsidianTop, Theme.obsidianBottom], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.emerald.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.successGradient, lineWidth: 1.5)
                )
        }
    }
}

// MARK: - Pieces

/// Native, system-driven countdown (keeps ticking while the app is suspended).
struct BreakCountdownText: View {
    let endTime: Date
    var isStale = false

    var body: some View {
        Group {
            if isStale || endTime <= .now {
                Text("0:00")
            } else {
                Text(timerInterval: Date.now...endTime, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(.white)
    }
}

struct BreakProgressBar: View {
    let start: Date
    let end: Date

    var body: some View {
        // ProgressView(timerInterval:) animates on its own, like the countdown text.
        ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(Theme.emerald)
        .labelsHidden()
    }
}

struct BreakPassIcon: View {
    let iconName: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.successGradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.emerald.opacity(0.55), radius: 8)
    }
}

// MARK: - Previews

private extension BreakPassAttributes {
    static let preview = BreakPassAttributes(passID: UUID().uuidString, startTime: .now)
}

private extension BreakPassAttributes.ContentState {
    static let gaming = BreakPassAttributes.ContentState(
        endTime: .now.addingTimeInterval(60 * 60),
        passTitle: "1-Hour Gaming / Movie Session",
        iconName: "gamecontroller.fill"
    )
}

#Preview("Lock Screen", as: .content, using: BreakPassAttributes.preview) {
    BreakPassLiveActivity()
} contentStates: {
    BreakPassAttributes.ContentState.gaming
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: BreakPassAttributes.preview) {
    BreakPassLiveActivity()
} contentStates: {
    BreakPassAttributes.ContentState.gaming
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: BreakPassAttributes.preview) {
    BreakPassLiveActivity()
} contentStates: {
    BreakPassAttributes.ContentState.gaming
}
#endif
