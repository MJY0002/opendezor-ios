import SwiftUI
import AVFoundation

public struct CustomPlayerView: View {
    @ObservedObject var playerService: PlayerService = .shared
    public var onDismiss: () -> Void
    
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var doubleTapFeedbackLeft: Bool = false
    @State private var doubleTapFeedbackRight: Bool = false
    @State private var dismissedNextEpisodePill: Bool = false
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Video Layer
                PlayerLayerRepresentable(playerService: playerService)
                    .ignoresSafeArea()
                
                // Subtitle Display Overlay (Bottom Centered)
                if let cueText = playerService.currentSubtitleCueText, !cueText.isEmpty {
                    VStack {
                        Spacer()
                        Text(cueText)
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.75))
                            )
                            .padding(.horizontal, 32)
                            .padding(.bottom, showControls ? 120 : 40)
                            .animation(.easeInOut(duration: 0.2), value: showControls)
                    }
                    .allowsHitTesting(false)
                }
                
                // Next Episode Binge Banner (Bottom-Right, when series near end)
                if playerService.currentItemSeason != nil &&
                    playerService.duration > 60 &&
                    (playerService.duration - playerService.currentTime) <= 35 &&
                    (playerService.duration - playerService.currentTime) > 1 &&
                    !dismissedNextEpisodePill {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 10) {
                                Button(action: {
                                    Task { @MainActor in
                                        await AppState.shared.playNextEpisodeIfEnabled()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "forward.end.fill")
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(L("Nächste Folge"))
                                                .appFont(size: 12, weight: .bold)
                                            Text("\(Int(playerService.duration - playerService.currentTime))s")
                                                .appFont(size: 10, design: .monospaced)
                                                .foregroundColor(AppTheme.cyanAccent)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.accentGradient)
                                    .cornerRadius(16)
                                }
                                
                                Button(action: {
                                    withAnimation { dismissedNextEpisodePill = true }
                                }) {
                                    Image(systemName: "xmark")
                                        .appFont(size: 11, weight: .bold)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .padding(6)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black.opacity(0.85))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                            .padding(.trailing, 20)
                            .padding(.bottom, showControls ? 110 : 30)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                
                // Double Tap Left / Right Feedback Icons
                HStack {
                    if doubleTapFeedbackLeft {
                        VStack(spacing: 4) {
                            Image(systemName: "gobackward.10")
                                .appFont(size: 36, weight: .bold)
                            Text("-10s")
                                .appFont(size: 13, weight: .bold)
                        }
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    if doubleTapFeedbackRight {
                        VStack(spacing: 4) {
                            Image(systemName: "goforward.10")
                                .appFont(size: 36, weight: .bold)
                            Text("+10s")
                                .appFont(size: 13, weight: .bold)
                        }
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 60)
                .allowsHitTesting(false)
                
                // Error Overlay
                if let err = playerService.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .appFont(size: 44)
                            .foregroundColor(AppTheme.destructive)
                        
                        Text(L("Wiedergabefehler"))
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.white)
                        
                        Text(err)
                            .appFont(size: 14)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(L("Schließen")) {
                            playerService.stopAndCleanup()
                            onDismiss()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppTheme.accentGradient)
                        .cornerRadius(20)
                        .foregroundColor(.white)
                    }
                    .padding(30)
                    .glassCard(cornerRadius: 20)
                    .padding(40)
                }
                
                // Overlay Controls — always in the tree, faded and made untappable when
                // hidden. Inserting/removing it with a transition left the old controls on
                // screen while the removal animation was repeatedly interrupted by the 4 Hz
                // time updates: they looked live but no longer received taps, so pause,
                // back and every other player button seemed dead.
                OverlayControlsView(playerService: playerService, onDismiss: {
                    playerService.stopAndCleanup()
                    onDismiss()
                })
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .accessibilityHidden(!showControls)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                handleDoubleTap(at: location, totalWidth: geometry.size.width)
            }
            .onTapGesture(count: 1) {
                toggleControlsVisibility()
            }
        }
        .onAppear {
            startHideControlsTimer()
            dismissedNextEpisodePill = false
        }
        .onChange(of: playerService.currentItemEpisode) {
            dismissedNextEpisodePill = false
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }
    
    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            startHideControlsTimer()
        } else {
            controlsTimer?.invalidate()
        }
    }
    
    private func startHideControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                if self.playerService.isPlaying && !self.playerService.isBuffering {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.showControls = false
                    }
                }
            }
        }
    }
    
    private func handleDoubleTap(at location: CGPoint, totalWidth: CGFloat) {
        guard !playerService.isLive else { return }
        if location.x < totalWidth / 2 {
            // Left half: Rewind 10s
            playerService.skipBackward(seconds: 10)
            withAnimation(AppMotion.press) {
                doubleTapFeedbackLeft = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { doubleTapFeedbackLeft = false }
            }
        } else {
            // Right half: Forward 10s
            playerService.skipForward(seconds: 10)
            withAnimation(AppMotion.press) {
                doubleTapFeedbackRight = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { doubleTapFeedbackRight = false }
            }
        }
        startHideControlsTimer()
    }
}
