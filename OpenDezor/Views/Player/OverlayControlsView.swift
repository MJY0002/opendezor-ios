import SwiftUI
import AVFoundation

@MainActor
public struct OverlayControlsView: View {
    @ObservedObject var playerService: PlayerService
    public var onDismiss: () -> Void
    @State private var showTracksSheet: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    
    public init(playerService: PlayerService, onDismiss: @escaping () -> Void) {
        self.playerService = playerService
        self.onDismiss = onDismiss
    }
    
    public init(onDismiss: @escaping () -> Void) {
        self.init(playerService: .shared, onDismiss: onDismiss)
    }
    
    public var body: some View {
        ZStack {
            // Dark gradient overlays top & bottom
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
                
                Spacer()
                
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // Top Bar
                topBar
                
                Spacer()
                
                // Center Controls
                centerControls
                
                Spacer()
                
                // Bottom Bar with Scrubber & Actions
                bottomBar
            }
        }
        // Controls sit on the video: a dark material, not flat black discs, lets the picture
        // show through while keeping the glyphs legible — in light mode too.
        .environment(\.colorScheme, .dark)
        .buttonStyle(ScaleCardButtonStyle())
        .sheet(isPresented: $showTracksSheet) {
            TracksSheetView(playerService: playerService)
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .accessibilityLabel(L("Schließen und zurück"))
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playerService.currentItemTitle)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if !playerService.currentItemSubtitle.isEmpty {
                    Text(playerService.currentItemSubtitle)
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // AirPlay Picker
            AirPlayRoutePickerView()
                .frame(width: 36, height: 36)
            
            // PiP Button
            #if os(iOS)
            if playerService.isPictureInPicturePossible {
                Button(action: {
                    playerService.togglePictureInPicture()
                }) {
                    Image(systemName: "pip.enter")
                        .accessibilityLabel(L("Bild-in-Bild"))
                        .appFont(size: 16, weight: .medium)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
            #endif
            
            // Sleep Timer
            Menu {
                Button(L("Timer aus")) {
                    playerService.setSleepTimer(minutes: nil)
                }
                Divider()
                ForEach([15, 30, 45, 60], id: \.self) { mins in
                    Button("\(mins) \(L("Min."))") {
                        playerService.setSleepTimer(minutes: mins)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: playerService.sleepTimerMinutesRemaining != nil ? "moon.fill" : "moon")
                        .appFont(size: 14)
                    if let rem = playerService.sleepTimerMinutesRemaining {
                        Text("\(rem)m")
                            .appFont(size: 11, weight: .bold)
                    }
                }
                .foregroundColor(playerService.sleepTimerMinutesRemaining != nil ? AppTheme.warning : .white)
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(Capsule().fill(.ultraThinMaterial))
            }
            
            // External Player
            if let streamUrl = playerService.currentStreamUrl, !playerService.isRoutedThroughVPN {
                Menu {
                    Button("VLC") {
                        openInExternalPlayer(scheme: "vlc-x-callback://url=\(streamUrl.absoluteString)")
                    }
                    Button("Infuse") {
                        openInExternalPlayer(scheme: "infuse://control/open?url=\(streamUrl.absoluteString)")
                    }
                    Button("Outplayer") {
                        openInExternalPlayer(scheme: "outplayer://\(streamUrl.absoluteString)")
                    }
                } label: {
                    Image(systemName: "arrow.up.right.video")
                        .accessibilityLabel(L("In externem Player öffnen"))
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
            
            // Tracks (Audio / Subtitles) Button
            Button(action: {
                showTracksSheet = true
            }) {
                Image(systemName: "captions.bubble.fill")
                    .accessibilityLabel(L("Untertitel und Tonspuren"))
                    .appFont(size: 16, weight: .medium)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - Center Controls
    private var centerControls: some View {
        HStack(spacing: 24) {
            // 10s Rewind
            if !playerService.isLive {
            Button(action: {
                playerService.skipBackward(seconds: 10)
            }) {
                Image(systemName: "gobackward.10")
                    .accessibilityLabel(L("10 Sekunden zurück"))
                    .appFont(size: 26, weight: .medium)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            }
            
            // Play / Pause / Buffering
            ZStack {
                if playerService.isBuffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.cyanAccent))
                        .scaleEffect(1.6)
                        .frame(width: 70, height: 70)
                } else {
                    Button(action: {
                        playerService.togglePlayPause()
                    }) {
                        Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .accessibilityLabel(playerService.isPlaying ? L("Pause") : L("Abspielen"))
                            .appFont(size: 34, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                Circle()
                                    .fill(AppTheme.accentGradient)
                                    .shadow(color: AppTheme.primaryAccent.opacity(0.5), radius: 10, x: 0, y: 4)
                            )
                    }
                }
            }
            
            if !playerService.isLive {
            // 10s Fast Forward
            Button(action: {
                playerService.skipForward(seconds: 10)
            }) {
                Image(systemName: "goforward.10")
                    .accessibilityLabel(L("10 Sekunden vor"))
                    .appFont(size: 26, weight: .medium)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            // Intro Skip (+85s)
            Button(action: {
                playerService.skipForward(seconds: 85)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "forward.fill")
                        .appFont(size: 11)
                    Text("+85s")
                        .appFont(size: 12, weight: .bold)
                }
                .accessibilityLabel(L("Intro überspringen (+85s)"))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Capsule().fill(.ultraThinMaterial))
            }
            }
        }
    }
    
    private func openInExternalPlayer(scheme: String) {
        if let url = URL(string: scheme) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if playerService.isLive {
                HStack(spacing: 6) {
                    LiveBadge()
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            } else {
            // Scrubber
            HStack(spacing: 12) {
                Text(formatTime(isScrubbing ? scrubTime : playerService.currentTime))
                    .appFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundColor(.white)
                
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let current = isScrubbing ? scrubTime : playerService.currentTime
                    let duration = max(playerService.duration, 1.0)
                    let progressRatio = min(max(current / duration, 0.0), 1.0)
                    let bufferRatio = min(max(playerService.bufferedTime / duration, 0.0), 1.0)
                    
                    ZStack(alignment: .leading) {
                        // Background Bar
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 5)
                        
                        // Buffer Bar
                        Capsule()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: totalWidth * CGFloat(bufferRatio), height: 5)
                        
                        // Progress Bar
                        Capsule()
                            .fill(AppTheme.accentGradient)
                            .frame(width: totalWidth * CGFloat(progressRatio), height: 5)
                        
                        // Thumb
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: Color.black.opacity(0.4), radius: 3)
                            .offset(x: max(0, min(totalWidth * CGFloat(progressRatio) - 7, totalWidth - 14)))
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                let clampedX = max(0, min(value.location.x, totalWidth))
                                let newRatio = clampedX / totalWidth
                                scrubTime = Double(newRatio) * duration
                            }
                            .onEnded { value in
                                let clampedX = max(0, min(value.location.x, totalWidth))
                                let newRatio = clampedX / totalWidth
                                let finalTime = Double(newRatio) * duration
                                playerService.seek(to: finalTime)
                                isScrubbing = false
                            }
                    )
                }
                .frame(height: 24)
                
                Text(formatTime(playerService.duration))
                    .appFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundColor(AppTheme.textSecondary)
            }
            }
            
            // Bottom Action Options (Aspect Ratio & Speed)
            HStack {
                // Aspect Ratio Toggle
                Button(action: {
                    playerService.toggleVideoGravity()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: playerService.videoGravity == .resizeAspect ? "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left" : "arrow.down.right.and.arrow.up.left")
                            .accessibilityLabel(L("Bildausschnitt anpassen"))
                            .appFont(size: 12)
                        Text(playerService.videoGravity == .resizeAspect ? "Fit" : "Fill")
                            .appFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                }
                
                Spacer()
                
                // Playback Speed Menu — a live edge cannot be played faster than it arrives.
                if !playerService.isLive {
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(action: {
                            playerService.setPlaybackRate(Float(speed))
                        }) {
                            HStack {
                                Text("\(String(format: "%.2fx", speed))")
                                if playerService.playbackRate == Float(speed) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle")
                            .accessibilityLabel(L("Wiedergabegeschwindigkeit"))
                            .appFont(size: 12)
                        Text(String(format: "%.2fx", playerService.playbackRate))
                            .appFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Time Formatter
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
