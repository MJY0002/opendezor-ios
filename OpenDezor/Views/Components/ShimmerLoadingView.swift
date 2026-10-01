import SwiftUI

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.8
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.18),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: phase * geo.size.width)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.6)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.2
                }
            }
    }
}

public extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

public struct CardSkeletonView: View {
    public var width: CGFloat = 140
    public var height: CGFloat = 210
    
    public init(width: CGFloat = 140, height: CGFloat = 210) {
        self.width = width
        self.height = height
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceLight)
                .frame(width: width, height: height)
                .shimmer()
            
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.surfaceLight)
                .frame(width: width * 0.85, height: 14)
                .shimmer()
            
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.surfaceLight.opacity(0.7))
                .frame(width: width * 0.5, height: 10)
                .shimmer()
        }
        .frame(width: width)
    }
}
