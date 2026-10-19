import SwiftUI

/// Wizard theme: midnight ink, enchanted gold and parchment.
enum Theme {
    /// Enchanted gold: deep and readable on parchment, bright on midnight.
    static let accent = Color.adaptive(light: NSColor(red: 0.60, green: 0.42, blue: 0.06, alpha: 1),
                                       dark: NSColor(red: 0.95, green: 0.78, blue: 0.37, alpha: 1))
    static let accentSoft = Color.adaptive(light: NSColor(red: 0.85, green: 0.65, blue: 0.20, alpha: 0.16),
                                           dark: NSColor(red: 0.95, green: 0.78, blue: 0.37, alpha: 0.14))
    /// Spell light: the gold of the quill in the icon.
    static let gold = Color(red: 0.95, green: 0.77, blue: 0.37)
    static let goldDeep = Color(red: 0.85, green: 0.60, blue: 0.17)
    static let violet = Color(red: 0.55, green: 0.40, blue: 0.95)
    static let ink = Color(red: 0.10, green: 0.08, blue: 0.25)
    /// The icon's night sky, for marks and highlights.
    static let gradient = LinearGradient(colors: [Color(red: 0.16, green: 0.11, blue: 0.37), Color(red: 0.06, green: 0.04, blue: 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.62), gold, goldDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warm = Color(red: 0.93, green: 0.45, blue: 0.24)

    /// Page and card surfaces: parchment by day, midnight by night.
    static let page = Color.adaptive(light: NSColor(red: 0.985, green: 0.97, blue: 0.935, alpha: 1),
                                     dark: NSColor(red: 0.085, green: 0.075, blue: 0.12, alpha: 1))
    static let card = Color.adaptive(light: NSColor(red: 1.0, green: 0.995, blue: 0.975, alpha: 1),
                                     dark: NSColor(red: 0.13, green: 0.115, blue: 0.18, alpha: 1))
    static let hairline = Color.adaptive(light: NSColor(red: 0.62, green: 0.48, blue: 0.20, alpha: 0.20),
                                         dark: NSColor(red: 0.95, green: 0.78, blue: 0.37, alpha: 0.14))

    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .semibold, design: .serif) }
}

extension Color {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// Rounded card used for grouped content across the main window.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accentSoft))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
    }
}

/// Gold, like a lit wand tip.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.goldGradient))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: Theme.goldDeep.opacity(0.35), radius: configuration.isPressed ? 2 : 6, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.accentSoft.opacity(configuration.isPressed ? 1.6 : 1)))
            .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

enum BrandMark {
    /// Monochrome template image for the menu bar: a wand with stars.
    static func menuBarImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Inscribo")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// The real app icon from the bundle (design/app-icon.svg), when running as Inscribo.app.
    static let iconImage: NSImage? = Bundle.main.image(forResource: "AppIcon")
}

/// The app icon. Uses the bundled icon artwork; falls back to a drawn night-sky tile with a quill.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = BrandMark.iconImage {
                // The icon art has ~10% transparent margin; zoom so the tile fills the frame.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(1.22)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(Theme.gradient)
                    .overlay(
                        Image(systemName: "pencil.and.scribble")
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(Theme.goldGradient)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}
