import SwiftUI
import AVFoundation
#if canImport(AVKit)
import AVKit
#endif

#if os(iOS)
import UIKit

// MARK: - iOS Player Layer UIView
public class PlayerUIView: UIView {
    public override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    public var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }
}

@MainActor
public struct PlayerLayerRepresentable: UIViewRepresentable {
    @ObservedObject var playerService: PlayerService
    
    public init(playerService: PlayerService) {
        self.playerService = playerService
    }
    
    public init() {
        self.init(playerService: .shared)
    }
    
    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .black
        view.player = playerService.player
        view.videoGravity = playerService.videoGravity
        playerService.setupPictureInPicture(with: view.playerLayer)
        return view
    }
    
    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.player != playerService.player {
            uiView.player = playerService.player
            playerService.setupPictureInPicture(with: uiView.playerLayer)
        }
        uiView.videoGravity = playerService.videoGravity
    }
}

// MARK: - AirPlay Route Picker iOS
public struct AirPlayRoutePickerView: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(AppTheme.cyanAccent)
        picker.prioritizesVideoDevices = true
        return picker
    }
    
    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

#elseif os(macOS)
import AppKit

public class PlayerNSView: NSView {
    public let playerLayer = AVPlayerLayer()
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

@MainActor
public struct PlayerLayerRepresentable: NSViewRepresentable {
    @ObservedObject var playerService: PlayerService
    
    public init(playerService: PlayerService) {
        self.playerService = playerService
    }
    
    public init() {
        self.init(playerService: .shared)
    }
    
    public func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = playerService.player
        view.playerLayer.videoGravity = playerService.videoGravity
        return view
    }
    
    public func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = playerService.player
        nsView.playerLayer.videoGravity = playerService.videoGravity
    }
}

public struct AirPlayRoutePickerView: View {
    public init() {}
    public var body: some View {
        Image(systemName: "airplayvideo")
            .appFont(size: 18)
            .foregroundColor(.white)
    }
}
#endif
