import SwiftData
import SwiftUI

/// Ticket outline with semicircular notches cut into both sides at `notchY`.
struct TicketShape: Shape {
    /// Distance of the notch centers from the top edge; `0` centers them vertically.
    var notchY: CGFloat = 0
    var notchRadius: CGFloat = 14
    var cornerRadius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)
        let n = notchRadius
        let y = notchY > 0 ? min(rect.minY + notchY, rect.maxY - r - n) : rect.midY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: y - n))
        path.addArc(center: CGPoint(x: rect.maxX, y: y), radius: n,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: y + n))
        path.addArc(center: CGPoint(x: rect.minX, y: y), radius: n,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Celebratory voucher shown when a reward is claimed (or reopened from history).
struct GuiltFreePassView: View {
    @Environment(\.dismiss) private var dismiss
    let redemption: RewardRedemption
    /// The wallet entry for this voucher (V4 passes); drives the break timer.
    @Query private var passes: [ActivePass]

    @State private var hasAppeared = false
    @State private var shine = false
    /// Height of the ticket's top section, so the notches line up with the perforation.
    @State private var topHeight: CGFloat = 0

    init(redemption: RewardRedemption) {
        self.redemption = redemption
        let id = redemption.id
        _passes = Query(filter: #Predicate<ActivePass> { $0.redemptionID == id })
    }

    private var pass: ActivePass? { passes.first }

    private var isActive: Bool {
        if let pass { return pass.status() != .used }
        return Calendar.current.isDateInToday(redemption.redeemedAt)
    }

    private var colors: [Color] {
        switch redemption.kind {
        case .dailyCheckpoint: Theme.successColors
        case .mysteryCrate: pass?.rarity.colors ?? Theme.legendaryColors
        case .shopReward: Theme.primaryColors
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ticket
                        .scaleEffect(hasAppeared ? 1 : 0.6)
                        .rotation3DEffect(.degrees(hasAppeared ? 0 : 25), axis: (x: 1, y: 0, z: 0))
                        .opacity(hasAppeared ? 1 : 0)

                    if let pass {
                        BreakTimerControls(pass: pass)
                            .padding(.horizontal, 8)
                    }

                    Text("Enjoy it—no guilt. You earned this.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(Theme.rounded(.headline))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.diagonal(colors), in: Capsule())
                            .shadow(color: (colors.last ?? Theme.violet).opacity(0.5), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.obsidianTop)
        .macSheetFrame(width: 440, height: 700)
        .sensoryFeedback(.success, trigger: hasAppeared) { _, appeared in appeared }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.6)) {
                shine = true
            }
        }
    }

    // MARK: Ticket

    private var ticket: some View {
        let shape = TicketShape(notchY: topHeight)

        return VStack(spacing: 0) {
            // Top: the reward
            VStack(spacing: 14) {
                HStack {
                    Text("GUILT-FREE PASS")
                        .font(.caption.weight(.heavy))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    statusPill
                }

                GradientIcon(systemName: redemption.iconName, colors: [.white.opacity(0.35), .white.opacity(0.12)], size: 76)

                Text(redemption.title)
                    .font(Theme.rounded(.title2))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !redemption.details.isEmpty {
                    Text(redemption.details)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                topHeight = height
            }

            // Perforation
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: 1)
                .padding(.horizontal, 22)

            // Stub: the details
            VStack(spacing: 12) {
                stubRow(label: "Issued", value: redemption.redeemedAt.formatted(date: .abbreviated, time: .shortened))
                if let minutes = redemption.durationMinutes {
                    stubRow(label: "Length", value: BreakPolicy.label(for: minutes))
                }
                stubRow(label: "Paid", value: paidText)
                stubRow(label: "Pass No.", value: redemption.passCode, monospaced: true)
            }
            .padding(22)
        }
        .background(
            ZStack {
                Theme.diagonal(colors)
                // Sweeping specular shine
                LinearGradient(
                    colors: [.clear, .white.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 120)
                .rotationEffect(.degrees(20))
                .offset(x: shine ? 360 : -360)
                .blendMode(.plusLighter)
            }
        )
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 1))
        .shadow(color: (colors.last ?? Theme.violet).opacity(0.45), radius: 28, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var paidText: String {
        switch redemption.kind {
        case .dailyCheckpoint: "Daily checkpoint · Free"
        case .mysteryCrate: "\(redemption.pointsSpent) pts · Mystery Crate"
        case .shopReward: "\(redemption.pointsSpent) Leisure Points"
        }
    }

    private var statusText: String {
        guard let pass else { return isActive ? "ACTIVE" : "REDEEMED" }
        switch pass.status() {
        case .saved: return pass.source == .mysteryCrate ? pass.rarity.title.uppercased() : "SAVED"
        case .running: return "ON BREAK"
        case .used: return "REDEEMED"
        }
    }

    private var statusPill: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(isActive ? Color.white : .white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(isActive ? 0.28 : 0.14)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }

    private func stubRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced, weight: .semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview("Guilt-Free Pass") {
    GuiltFreePassView(redemption: PreviewSampleData.sampleRedemption)
        .previewEnvironment()
}
