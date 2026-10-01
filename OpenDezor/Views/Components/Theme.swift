import SwiftUI
import Combine

// MARK: - Theme Controller
//
// AppTheme used to be a bag of `static let` colors, which meant the palette could never
// change at runtime. The properties are now computed from `ThemeController.shared`, so
// every existing `AppTheme.background` call site keeps working while picking up the
// user's colour-scheme and accent choice.

/// Not actor-isolated on purpose: `AppTheme`'s colour lookups are read from view bodies,
/// default argument values and modifiers that are not MainActor-isolated. Writes only ever
/// happen from the main thread (settings screen, onboarding, StorageService).
public final class ThemeController: ObservableObject {
    public static let shared = ThemeController()

    @Published public var colorScheme: AppColorScheme = .dark
    @Published public var accent: AppAccent = .indigo

    public init() {}

    /// Resolved light/dark decision. `.system` follows the device trait, which is read
    /// from the environment by `ThemeSyncModifier`.
    @Published public var systemIsDark: Bool = true

    public var isDark: Bool {
        switch colorScheme {
        case .dark: return true
        case .light: return false
        case .system: return systemIsDark
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    public func apply(_ settings: AppSettings) {
        if colorScheme != settings.colorScheme { colorScheme = settings.colorScheme }
        if accent != settings.accent { accent = settings.accent }
    }
}

// MARK: - Accent Palettes
public extension AppAccent {
    /// (primary, deeper shade, lighter tint) of one hue.
    ///
    /// One hue per accent on purpose: the old pairs mixed indigo with pink and cyan, and
    /// every gradient button and highlight came out in a different colour.
    var colors: (Color, Color, Color) {
        switch self {
        case .indigo:
            return (Color(red: 0.37, green: 0.36, blue: 0.90),   // #5E5CE6
                    Color(red: 0.29, green: 0.28, blue: 0.76),
                    Color(red: 0.62, green: 0.61, blue: 0.98))
        case .crimson:
            return (Color(red: 0.90, green: 0.11, blue: 0.20),   // cinema red
                    Color(red: 0.71, green: 0.06, blue: 0.13),
                    Color(red: 1.00, green: 0.47, blue: 0.50))
        case .emerald:
            return (Color(red: 0.11, green: 0.72, blue: 0.47),
                    Color(red: 0.07, green: 0.55, blue: 0.35),
                    Color(red: 0.46, green: 0.87, blue: 0.67))
        case .amber:
            return (Color(red: 0.96, green: 0.62, blue: 0.10),
                    Color(red: 0.83, green: 0.46, blue: 0.04),
                    Color(red: 1.00, green: 0.80, blue: 0.42))
        case .violet:
            return (Color(red: 0.58, green: 0.35, blue: 0.95),
                    Color(red: 0.45, green: 0.24, blue: 0.80),
                    Color(red: 0.76, green: 0.62, blue: 1.00))
        }
    }

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .crimson: return "Karmin"
        case .emerald: return "Smaragd"
        case .amber: return "Bernstein"
        case .violet: return "Violett"
        }
    }

    /// Swatch shown in the picker.
    var previewGradient: LinearGradient {
        let (a, b, _) = colors
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - App Color Palette & Theme
public struct AppTheme {
    private static var t: ThemeController { .shared }
    private static var dark: Bool { t.isDark }
    static var isDarkPalette: Bool { dark }

    // Surfaces
    public static var background: Color {
        dark ? Color(red: 0.04, green: 0.04, blue: 0.05) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    public static var surface: Color {
        dark ? Color(red: 0.09, green: 0.09, blue: 0.11) : Color.white
    }
    public static var surfaceLight: Color {
        dark ? Color(red: 0.15, green: 0.15, blue: 0.18) : Color(red: 0.90, green: 0.90, blue: 0.92)
    }
    public static var surfaceBorder: Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    // Accents follow the user's pick
    public static var primaryAccent: Color { t.accent.colors.0 }
    public static var secondaryAccent: Color { t.accent.colors.1 }
    /// Highlight colour for icons, links and selection. The light tint only reads on a
    /// dark page; on a light one the full-strength accent keeps its contrast.
    public static var cyanAccent: Color { dark ? t.accent.colors.2 : t.accent.colors.0 }

    // Fixed semantic colors
    public static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    public static let warning = Color(red: 0.98, green: 0.65, blue: 0.18)
    public static let destructive = Color(red: 0.94, green: 0.27, blue: 0.27)

    // Text
    public static var textPrimary: Color {
        dark ? Color.white : Color(red: 0.07, green: 0.08, blue: 0.11)
    }
    public static var textSecondary: Color {
        dark ? Color(red: 0.68, green: 0.68, blue: 0.72) : Color(red: 0.33, green: 0.33, blue: 0.38)
    }
    public static var textTertiary: Color {
        dark ? Color(red: 0.45, green: 0.45, blue: 0.50) : Color(red: 0.55, green: 0.55, blue: 0.60)
    }

    public static var accentGradient: LinearGradient {
        // Barely a gradient: a single hue with a little depth, not a two-colour sweep.
        LinearGradient(colors: [primaryAccent, secondaryAccent], startPoint: .top, endPoint: .bottom)
    }

    public static var cyanGradient: LinearGradient {
        LinearGradient(colors: [cyanAccent, primaryAccent], startPoint: .leading, endPoint: .trailing)
    }

    /// Scrim laid over artwork so the text on top of it stays legible.
    ///
    /// Deliberately black in both themes rather than fading to `background`: what is being
    /// darkened is the artwork, not the page. Fading to a near-white background in light
    /// mode produced no scrim at all and left the hero title unreadable over bright images.
    public static var heroBackdropGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color.black.opacity(0.30), location: 0.45),
                .init(color: Color.black.opacity(0.72), location: 0.78),
                .init(color: Color.black.opacity(0.88), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Fill for chips that sit on top of artwork. `surface` is white in light mode, and
    /// `BadgeView` always draws white text, so a surface-filled badge vanished there.
    public static var onArtworkChip: Color { Color.black.opacity(0.55) }
}

// MARK: - Typography

public extension AppTheme {
    /// Letter-spacing for a given size.
    ///
    /// Tracking is size-specific — one value for every size is wrong somewhere. As type
    /// grows the letters read too far apart and want to be pulled together; small text
    /// needs a touch more room to stay legible. Body sits at zero.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        switch size {
        case ..<13: return 0.2      // small labels and badges
        case ..<20: return 0        // body
        case ..<28: return -0.4     // headings
        default: return -0.8        // display
        }
    }
}

/// A size that follows the user's text-size setting, with the tracking that size wants.
///
/// `Font.system(size:)` is a *fixed* size and ignores Dynamic Type entirely — the app was
/// pixel-identical at the largest accessibility size. `@ScaledMetric` provides the scale
/// factor for the current setting, so the type grows with it while keeping the design's
/// proportions.
private struct AppFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .font(.system(size: size * scale, weight: weight, design: design))
            .tracking(AppTheme.tracking(forSize: size))
    }
}

public extension View {
    /// Size + tracking + Dynamic Type in one call, so the three can never drift apart.
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }

    /// Keyboard treatment for a field that takes a URL. Autocapitalising or autocorrecting
    /// an address mangles it, so every such field wants all three — and the platform gate
    /// belongs here rather than repeated at each call site.
    func urlField() -> some View {
        #if os(iOS)
        return self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        #else
        return self
        #endif
    }
}

// MARK: - Clear Field Button

/// The "×" affordance inside a text field.
///
/// Six fields each carried their own copy of this and only one of them had an
/// accessibility label, so to VoiceOver the other five were an unnamed button. One
/// component means one label.
public struct ClearFieldButton: View {
    private let size: CGFloat
    private let action: () -> Void

    public init(size: CGFloat = 14, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .appFont(size: size)
                .foregroundColor(AppTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Text löschen"))
    }
}

// MARK: - Motion

/// The app's motion vocabulary.
///
/// Apple designs springs with two parameters rather than mass/stiffness/damping: how much
/// it overshoots (damping) and how quickly it arrives (response). The rule that matters:
/// **overshoot has to be earned by momentum.** A menu that simply appeared should settle
/// without bouncing; a card the user flicked should overshoot, because that is what a
/// thrown object does. Everything here is critically damped unless a gesture preceded it.
///
/// Springs are also what makes motion interruptible — they animate from wherever the value
/// currently is, so a user can grab something mid-flight and redirect it without a jump.
/// Prefer these over `.easeInOut` for anything the user can touch.
public enum AppMotion {
    /// Critically damped, no overshoot. The default for appearing, dismissing and any
    /// state change the user did not throw.
    public static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)

    /// Slight overshoot — only after a flick, drag or throw.
    public static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Press feedback: fast enough to read as instant, no bounce on release.
    public static let press = Animation.spring(response: 0.25, dampingFraction: 1.0)
}

// MARK: - System Appearance Sync
/// Feeds the device's light/dark trait into ThemeController so `.system` resolves right.
public struct ThemeSyncModifier: ViewModifier {
    @Environment(\.colorScheme) private var environmentScheme
    @ObservedObject private var theme = ThemeController.shared

    public func body(content: Content) -> some View {
        // Only write on an actual change. `@Published` fires on every assignment, even a
        // no-op one, and this modifier sits on the root view — a needless publish here
        // invalidates the whole tree at launch, right while the launch animation is
        // playing. `ThemeController.apply` guards its other properties the same way.
        content
            .onAppear { syncIfNeeded(environmentScheme == .dark) }
            .onChange(of: environmentScheme) { _, newValue in
                syncIfNeeded(newValue == .dark)
            }
    }

    private func syncIfNeeded(_ isDark: Bool) {
        guard theme.systemIsDark != isDark else { return }
        theme.systemIsDark = isDark
    }
}

public extension View {
    func syncsSystemAppearance() -> some View {
        modifier(ThemeSyncModifier())
    }
}

// MARK: - Glassmorphism View Modifiers
public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var strokeColor: Color = Color.white.opacity(0.12)
    var fillColor: Color = AppTheme.surface.opacity(0.65)

    /// Translucency is a preference, not a given. With Reduce Transparency the material
    /// is dropped for a solid surface, and with Increase Contrast the edge becomes a
    /// defined border instead of a hairline catch-light.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var isSolid: Bool { reduceTransparency || contrast == .increased }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSolid ? AnyShapeStyle(AppTheme.surface) : AnyShapeStyle(fillColor))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(isSolid ? AnyShapeStyle(AppTheme.surface) : AnyShapeStyle(Material.ultraThin))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        contrast == .increased ? AppTheme.textSecondary : strokeColor,
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
                    // A Shape in an overlay hit-tests across its whole area, not just the
                    // stroke, and would swallow taps meant for the content underneath —
                    // which is what kept the omnibox text field from ever taking focus.
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(AppTheme.isDarkPalette ? 0.35 : 0.08), radius: 8, x: 0, y: 3)
    }
}

public struct GlassBackgroundModifier: ViewModifier {
    /// A flat page. The coloured radial glows it used to paint made every screen look
    /// washed out in light mode and competed with the artwork, which is the content.
    public func body(content: Content) -> some View {
        content.background(AppTheme.background.ignoresSafeArea())
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 16, strokeColor: Color = Color.white.opacity(0.12), fillColor: Color = AppTheme.surface.opacity(0.65)) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeColor: strokeColor, fillColor: fillColor))
    }
    
    func glassBackground() -> some View {
        self.modifier(GlassBackgroundModifier())
    }

    /// Horizontal rows that settle on a card edge instead of stopping mid-card, carrying
    /// the flick's momentum to the next one — the way App Store and TV rows behave. The
    /// inset lives in the scroll content margins so the snap aligns with it.
    func carouselSnapping() -> some View {
        self.contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
    }

    /// Fades and lifts the view in when it appears, `delay` seconds after the trigger.
    ///
    /// Used to stagger the parts of a screen so it assembles itself instead of snapping
    /// into place. Honours `accessibilityReduceMotion` by jumping straight to the end
    /// state — the content must always arrive, only the motion is optional.
    func appearsStaggered(delay: Double = 0) -> some View {
        self.modifier(StaggeredAppearModifier(delay: delay))
    }
}

private struct StaggeredAppearModifier: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(AppMotion.standard.delay(delay)) {
                    shown = true
                }
            }
    }
}

// MARK: - Showcase motion
//
// Scroll-driven and ambient motion. Everything here tracks the scroll position directly
// (1:1, interruptible by definition) or runs slowly in the background, and every piece
// steps aside for Reduce Motion.

private struct KenBurnsModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(zoomed ? 1.12 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                // One slow drift over ~40 s per cycle — well below the frequencies that
                // cause discomfort, and slow enough to read as the picture breathing.
                withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                    zoomed = true
                }
            }
    }
}

private struct ParallaxModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let factor: CGFloat

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.visualEffect { effect, proxy in
                effect.offset(y: -proxy.frame(in: .scrollView).minY * factor)
            }
        }
    }
}

private struct StretchyHeaderModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let height: CGFloat

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Pulling down past the top grows the artwork from its bottom edge instead of
            // revealing empty space; scrolling up lets it drift slower than the page.
            content.visualEffect { effect, proxy in
                let y = proxy.frame(in: .scrollView).minY
                return effect
                    .scaleEffect(y > 0 ? 1 + y / height : 1, anchor: .bottom)
                    .offset(y: y > 0 ? 0 : -y * 0.4)
            }
        }
    }
}

private struct CarouselDepthModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Cards turn slightly toward the centre and settle as they arrive — the row
            // reads as a physical strip rather than a flat list.
            content.scrollTransition(.interactive, axis: .horizontal) { effect, phase in
                effect
                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                    .opacity(phase.isIdentity ? 1 : 0.65)
                    .rotation3DEffect(.degrees(phase.value * -14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            }
        }
    }
}

private struct RevealOnScrollModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Sections rise into place as they scroll up from the bottom edge.
            content.scrollTransition(.animated(.spring(response: 0.5, dampingFraction: 1)), axis: .vertical) { effect, phase in
                effect
                    .opacity(phase.value > 0 ? 0.25 : 1)
                    .scaleEffect(phase.value > 0 ? 0.94 : 1, anchor: .top)
                    .offset(y: phase.value > 0 ? 28 : 0)
            }
        }
    }
}

public extension View {
    /// Slow, continuous zoom on hero artwork.
    func kenBurns() -> some View { modifier(KenBurnsModifier()) }
    /// Moves slower than the scroll, for artwork inside a clipped frame.
    func parallax(_ factor: CGFloat = 0.3) -> some View { modifier(ParallaxModifier(factor: factor)) }
    /// Header artwork that stretches on pull-down and drifts on scroll.
    func stretchyHeader(height: CGFloat) -> some View { modifier(StretchyHeaderModifier(height: height)) }
    /// 3D depth for cards in a horizontal row.
    func carouselDepth() -> some View { modifier(CarouselDepthModifier()) }
    /// Rise-in for vertically scrolling sections.
    func revealOnScroll() -> some View { modifier(RevealOnScrollModifier()) }
}

// MARK: - Poster → detail zoom

/// Namespace shared by every poster and the detail sheet, so a tapped card can grow into
/// the page it opens (and shrink back into it on dismiss). Set once, on the navigation root.
private struct MediaZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

public extension EnvironmentValues {
    var mediaZoomNamespace: Namespace.ID? {
        get { self[MediaZoomNamespaceKey.self] }
        set { self[MediaZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSourceModifier: ViewModifier {
    @Environment(\.mediaZoomNamespace) private var namespace
    let id: String

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    /// Marks artwork as the origin of the detail zoom (iOS 18+; a plain sheet before).
    func zoomSource(id: String) -> some View { modifier(ZoomSourceModifier(id: id)) }
    /// The detail side of that zoom.
    func zoomDestination(id: String, in namespace: Namespace.ID) -> some View {
        modifier(ZoomDestinationModifier(id: id, namespace: namespace))
    }
}
