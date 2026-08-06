import AppKit
import SwiftUI

struct BrandLogoImage: View {
    private let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .padding(9)
                    .background(.white)
                    .foregroundStyle(.black)
            }
        }
    }
}

enum CinematicTheme {
    static let canvas = Color(red: 0.075, green: 0.086, blue: 0.102)
    static let deepCanvas = Color(red: 0.012, green: 0.016, blue: 0.022)
    static let surface = Color.white.opacity(0.055)
    static let elevated = Color.white.opacity(0.085)
    static let divider = Color.white.opacity(0.10)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.60)
    static let tertiaryText = Color.white.opacity(0.36)
    static let accent = Color(red: 0.73, green: 0.81, blue: 1.0)
    static let success = Color(red: 0.33, green: 0.91, blue: 0.58)
    static let cardRadius: CGFloat = 28
    static let pageGutter: CGFloat = 48
    static let sectionSpacing: CGFloat = 68

    static func specularEdge(intensity: Double = 1, angle: Angle = .degrees(-150)) -> AngularGradient {
        AngularGradient(
            colors: [
                .clear,
                .white.opacity(0.08 * intensity),
                .white.opacity(0.64 * intensity),
                .white.opacity(0.05 * intensity),
                .clear,
                .black.opacity(0.22),
                .clear,
                .white.opacity(0.16 * intensity),
                .clear,
            ],
            center: .center,
            startAngle: angle,
            endAngle: .degrees(angle.degrees + 360)
        )
    }
}

struct WindowAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}

/// MenuBarExtra creates its own AppKit window and does not always honor
/// SwiftUI's preferred color scheme when resolving native Liquid Glass colors.
/// Pinning that window to Dark Aqua keeps its material and semantic colors in
/// sync with the app's always-dark player UI.
struct DarkPanelAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        window?.appearance = NSAppearance(named: .darkAqua)
    }
}

struct WindowMaterialBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A real Liquid Glass grouping surface on macOS 26. The container lets nearby
/// glass shapes sample and blend the same live backdrop instead of looking like
/// unrelated translucent rectangles.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func cinematicGlassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: Capsule()
            )
            // Native Liquid Glass already renders a live, pointer-reactive
            // specular rim. Drawing a full white stroke over it flattens the
            // refraction and makes the material look simulated.
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(CinematicTheme.specularEdge(), lineWidth: 0.85) }
                .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    func cinematicGlassCircle(interactive: Bool = true, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: Circle()
            )
            .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(CinematicTheme.specularEdge(), lineWidth: 0.85) }
                .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    func cinematicGlassPanel(cornerRadius: CGFloat = 28, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(CinematicTheme.specularEdge(), lineWidth: 0.85)
                }
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: UInt64
        switch cleaned.count {
        case 3:
            (red, green, blue) = (((value >> 8) & 0xF) * 17, ((value >> 4) & 0xF) * 17, (value & 0xF) * 17)
        default:
            (red, green, blue) = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }
}

struct CinematicButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        CinematicButtonBody(label: configuration.label, isPressed: configuration.isPressed, prominent: prominent)
    }
}

private struct CinematicButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let prominent: Bool
    @State private var isHovering = false

    var body: some View {
        visualBody
            .contentShape(Capsule())
            .scaleEffect(isPressed ? 0.965 : (isHovering ? 1.025 : 1))
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: isPressed)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
    }

    private var sizedLabel: some View {
        label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 48)
    }

    @ViewBuilder
    private var visualBody: some View {
        if prominent {
            sizedLabel
                .foregroundStyle(Color.black)
                .background(Color.white.opacity(isPressed ? 0.80 : (isHovering ? 1 : 0.94)), in: Capsule())
                .overlay(alignment: .top) {
                    Capsule().trim(from: 0.08, to: 0.42)
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                        .blur(radius: 0.3)
                }
        } else {
            sizedLabel
                .foregroundStyle(CinematicTheme.primaryText)
                .cinematicGlassCapsule(interactive: true, tint: .black.opacity(0.06))
        }
    }
}

struct CinematicInteractiveButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.035
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        CinematicInteractiveButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            hoverScale: hoverScale,
            pressedScale: pressedScale
        )
    }
}

private struct CinematicInteractiveButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let hoverScale: CGFloat
    let pressedScale: CGFloat
    @State private var isHovering = false

    var body: some View {
        label
            .contentShape(Rectangle())
            .brightness(isHovering ? 0.07 : 0)
            .opacity(isPressed ? 0.78 : 1)
            .scaleEffect(isPressed ? pressedScale : (isHovering ? hoverScale : 1))
            .animation(.snappy(duration: 0.20, extraBounce: 0.02), value: isHovering)
            .animation(.snappy(duration: 0.14, extraBounce: 0), value: isPressed)
            .onHover { hovering in
                isHovering = hovering
                hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
    }
}
