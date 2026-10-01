import SwiftUI

/// Launch animation shown on every cold start, before either the onboarding or the main
/// interface appears. It runs on a timer rather than waiting for work to finish, so a slow
/// addon reload can never leave the user staring at it.
public struct LaunchAnimationView: View {
    public var onFinished: () -> Void

    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0.0
    @State private var glyphScale: CGFloat = 0.55
    @State private var glyphOpacity: Double = 0.0
    @State private var wordmarkOpacity: Double = 0.0
    @State private var wordmarkOffset: CGFloat = 14
    @State private var sweep: CGFloat = -1.0
    @State private var isLeaving: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var theme: ThemeController = .shared

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            // Soft accent bloom behind the mark
            RadialGradient(
                colors: [AppTheme.primaryAccent.opacity(0.35), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 260
            )
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.primaryAccent.opacity(0.28), lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: AppTheme.primaryAccent.opacity(0.5), radius: 24, x: 0, y: 10)
                        .scaleEffect(glyphScale)
                        .opacity(glyphOpacity)

                    Image(systemName: "play.tv.fill")
                        .appFont(size: 42, weight: .semibold)
                        .foregroundColor(.white)
                        .scaleEffect(glyphScale)
                        .opacity(glyphOpacity)
                }

                Text("OpenDezor")
                    .appFont(size: 32, weight: .heavy, design: .rounded)
                    .foregroundStyle(AppTheme.accentGradient)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
                    .overlay(
                        // A single light sweep across the wordmark
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.75), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 90)
                        .offset(x: sweep * 190)
                        .blendMode(.plusLighter)
                        .mask(
                            Text("OpenDezor")
                                .appFont(size: 32, weight: .heavy, design: .rounded)
                        )
                        // plusLighter brightens what is underneath, which reads as a
                        // highlight on a dark background but washes the wordmark out on a
                        // light one.
                        .opacity(reduceMotion || !theme.isDark ? 0 : wordmarkOpacity)
                    )
            }
            .scaleEffect(isLeaving ? 1.06 : 1.0)
            .opacity(isLeaving ? 0 : 1)
        }
        .onAppear(perform: run)
    }

    private func run() {
        guard !reduceMotion else {
            // Still show the mark briefly so the launch does not flash, but skip motion.
            ringScale = 1; ringOpacity = 1; glyphScale = 1; glyphOpacity = 1
            wordmarkOpacity = 1; wordmarkOffset = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onFinished() }
            return
        }

        withAnimation(.spring(response: 0.65, dampingFraction: 0.62)) {
            ringScale = 1.0
            ringOpacity = 1.0
            glyphScale = 1.0
            glyphOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.28)) {
            wordmarkOpacity = 1.0
            wordmarkOffset = 0
        }
        withAnimation(.easeInOut(duration: 0.85).delay(0.45)) {
            sweep = 1.0
        }
        // Hold the settled mark for a beat before leaving. Without the pause the wordmark
        // had only just finished sliding in when the exit started, so the intro read as a
        // flicker rather than an animation.
        withAnimation(.easeIn(duration: 0.4).delay(2.0)) {
            isLeaving = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            onFinished()
        }
    }
}
