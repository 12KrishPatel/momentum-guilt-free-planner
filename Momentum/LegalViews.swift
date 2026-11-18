import SwiftUI

/// Public links and app metadata shown in Profile › About.
enum AppInfo {
    static let privacyPolicyURL = URL(string: "https://12krishpatel.github.io/momentum-guilt-free-planner/privacy.html")!
    static let supportURL = URL(string: "https://12krishpatel.github.io/momentum-guilt-free-planner/support.html")!
    static let contactURL = URL(string: "https://github.com/12KrishPatel/momentum-guilt-free-planner/issues")!
    static let policyEffectiveDate = "November 17, 2026"

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

/// A titled block of text in a document page.
struct DocumentSection: Identifiable {
    let title: String
    let paragraphs: [String]
    var id: String { title }
}

// MARK: - Content (kept in sync with docs/privacy.html and docs/support.html)

enum LegalContent {
    static let privacySummary = "Momentum doesn't collect your data. Everything you enter stays on your devices and, if you use iCloud, in your own private iCloud account, which we can't access."

    static let privacy: [DocumentSection] = [
        DocumentSection(title: "What Momentum stores", paragraphs: [
            "Your tasks and notes, badges, XP and Leisure Points, Guilt-Free Passes, custom rewards, ritual history and reminder settings.",
            "This data is stored on your device, in a container shared only with Momentum's own widgets so they can show your tasks.",
        ]),
        DocumentSection(title: "iCloud sync", paragraphs: [
            "If you're signed in to iCloud, Momentum syncs your data between your devices using your private iCloud database (CloudKit). That data belongs to your Apple Account and is protected by Apple; the developer has no access to it. Apple's handling of iCloud data is covered by Apple's own privacy policy.",
            "You can turn sync off at any time in Settings › [your name] › iCloud.",
        ]),
        DocumentSection(title: "What Momentum doesn't do", paragraphs: [
            "No accounts or sign-up. No analytics, advertising or tracking. No third-party SDKs. Nothing is sent to the developer or to any server other than your own iCloud.",
            "Momentum does not sell, share or rent any information, because it never receives any.",
        ]),
        DocumentSection(title: "Notifications, widgets and Live Activities", paragraphs: [
            "Reminders and break-timer alerts are scheduled on your device. Widgets and Live Activities (the break timer on your Lock Screen and in the Dynamic Island) read the same on-device data and don't send it anywhere.",
        ]),
        DocumentSection(title: "Deleting your data", paragraphs: [
            "Use Profile › Erase All Data to delete everything in Momentum, including on your other devices that sync through iCloud.",
            "You can also delete the app, and remove its iCloud data in Settings › [your name] › iCloud › Manage Account Storage.",
        ]),
        DocumentSection(title: "Children", paragraphs: [
            "Momentum doesn't collect personal information from anyone, including children.",
        ]),
        DocumentSection(title: "Changes and contact", paragraphs: [
            "If this policy changes, the updated version will be posted on this page with a new effective date.",
            "Questions? Open an issue on the Momentum GitHub page (link below).",
        ]),
    ]

    static let support: [DocumentSection] = [
        DocumentSection(title: "Syncing between iPhone and Mac", paragraphs: [
            "Sign in to the same Apple Account with iCloud turned on, on every device. Changes usually appear within a minute; opening the app nudges a sync.",
        ]),
        DocumentSection(title: "Widgets", paragraphs: [
            "iPhone: touch and hold the Home Screen, tap Edit › Add Widget, and search for Momentum. Mac: right-click the desktop and choose Edit Widgets. You can check off tasks right from the widget.",
        ]),
        DocumentSection(title: "Break timers and the Dynamic Island", paragraphs: [
            "Open a timed Guilt-Free Pass and tap Start Break Timer. Every break lasts at least 30 minutes. If the countdown doesn't appear, turn on Live Activities in Settings › Momentum.",
        ]),
        DocumentSection(title: "Combos and Mystery Crates", paragraphs: [
            "Finish 2 tasks within 45 minutes for a 1.5x combo, 3 or more for 2.0x Overdrive. Clear all of today's tasks before 5 PM for a 1.5x Early Finisher bonus for the rest of the day.",
            "Mystery Crates cost Leisure Points (never money) and list their exact odds on the card.",
        ]),
        DocumentSection(title: "Sunday Reset and Morning Kickoff", paragraphs: [
            "Start either ritual from the Plan menu. Swipe through the cards to sort leftover tasks or confirm today's plan, and earn 25 XP once per day.",
        ]),
        DocumentSection(title: "Starting over", paragraphs: [
            "Profile › Erase All Data deletes everything on all your synced devices. It can't be undone.",
        ]),
        DocumentSection(title: "Contact", paragraphs: [
            "Found a bug or have an idea? Open an issue on the Momentum GitHub page (link below) and include your device and app version.",
        ]),
    ]
}

// MARK: - Views

/// Full-screen document sheet used for the privacy policy and support page.
struct DocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let icon: String
    let colors: [Color]
    var summary: String?
    var footnote: String?
    let sections: [DocumentSection]
    let webURL: URL
    var contactURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        GradientIcon(systemName: icon, colors: colors, size: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(Theme.rounded(.title2, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                            if let footnote {
                                Text(footnote)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    if let summary {
                        Text(summary)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 16, tint: colors.first)
                    }

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if let contactURL {
                            Link(destination: contactURL) {
                                linkLabel("Contact on GitHub", icon: "bubble.left.and.text.bubble.right.fill", filled: true)
                            }
                        }
                        Link(destination: webURL) {
                            linkLabel("View on the web", icon: "safari", filled: contactURL == nil)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.obsidianTop)
        .macSheetFrame(width: 560, height: 680)
    }

    private func linkLabel(_ text: String, icon: String, filled: Bool) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if filled {
                    Capsule().fill(Theme.diagonal(colors))
                } else {
                    Capsule().fill(Theme.chipBackground)
                }
            }
    }
}

enum AboutPage: String, Identifiable {
    case privacy
    case support

    var id: String { rawValue }
}

extension DocumentSheet {
    static func page(_ page: AboutPage) -> DocumentSheet {
        switch page {
        case .privacy:
            DocumentSheet(
                title: "Privacy Policy",
                icon: "hand.raised.fill",
                colors: Theme.successColors,
                summary: LegalContent.privacySummary,
                footnote: "Effective \(AppInfo.policyEffectiveDate)",
                sections: LegalContent.privacy,
                webURL: AppInfo.privacyPolicyURL,
                contactURL: AppInfo.contactURL
            )
        case .support:
            DocumentSheet(
                title: "Help & Support",
                icon: "questionmark.bubble.fill",
                colors: Theme.primaryColors,
                footnote: "Momentum \(AppInfo.versionString)",
                sections: LegalContent.support,
                webURL: AppInfo.supportURL,
                contactURL: AppInfo.contactURL
            )
        }
    }
}

#Preview("Privacy") {
    DocumentSheet.page(.privacy)
        .preferredColorScheme(.dark)
}
