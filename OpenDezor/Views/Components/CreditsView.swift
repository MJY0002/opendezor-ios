import SwiftUI

/// Author credit, shown at the end of onboarding and from the settings.
///
/// Motion follows the launch animation: a staggered spring entrance, and a slow heartbeat
/// on the mark. `accessibilityReduceMotion` drops straight to the final state — the credit
/// must still be readable, it just does not move.
public struct CreditsView: View {
    /// The one place the author's links are defined.
    public enum Author {
        public static let name = "MJY"
        public static let gitHubURL = URL(string: "https://github.com/MJY0002")!
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Phone landscape leaves roughly 390pt of height, so the credit collapses into a
    /// single row there instead of stacking three.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    @State private var heartScale: CGFloat = 1.0

    public init() {}

    public var body: some View {
        Group {
            if isCompactHeight {
                HStack(spacing: 14) {
                    madeWithLine
                    name
                    links
                }
            } else {
                VStack(spacing: 18) {
                    madeWithLine
                    name
                    links
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompactHeight ? 10 : 22)
        .appearsStaggered()
        .onAppear(perform: startHeartbeat)
    }

    private var name: some View {
        Text(Author.name)
            .font(.system(size: isCompactHeight ? 20 : 30, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.accentGradient)
    }

    private var links: some View {
        HStack(spacing: 12) {
            linkChip(
                title: "GitHub",
                systemImage: "chevron.left.forwardslash.chevron.right",
                url: Author.gitHubURL
            )
        }
    }

    private var madeWithLine: some View {
        HStack(spacing: 7) {
            Text(L("Gebaut mit"))
                .appFont(size: 15, weight: .medium)
                .foregroundColor(AppTheme.textSecondary)

            Image(systemName: "heart.fill")
                .appFont(size: 15)
                .foregroundColor(AppTheme.destructive)
                .scaleEffect(heartScale)

            Text(L("von"))
                .appFont(size: 15, weight: .medium)
                .foregroundColor(AppTheme.textSecondary)
        }
        // Read as one phrase instead of three fragments plus an image.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L("Gebaut mit")) \(L("Liebe")) \(L("von")) \(Author.name)")
    }

    @ViewBuilder
    private func linkChip(title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .appFont(size: 13, weight: .semibold)
                Text(title)
                    .appFont(size: 14, weight: .semibold)
            }
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 22)
        }
        .buttonStyle(ScaleCardButtonStyle())
    }

    /// The entrance is `.appearsStaggered()`; this is only the heartbeat on the mark —
    /// a slow double-thump, not a constant throb, so it reads once and then sits quietly
    /// in the corner of the eye.
    private func startHeartbeat() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.5)) {
            heartScale = 1.18
        }
    }
}
