import SwiftUI

enum Theme {
    static let accent = Color(red: 0.40, green: 0.36, blue: 1.00)
    static let accentSoft = Color(red: 0.40, green: 0.36, blue: 1.00).opacity(0.12)
    /// The app icon's violet → blue.
    static let gradient = LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 1.00),
                                                  Color(red: 0.18, green: 0.42, blue: 1.00)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warm = Color(red: 0.98, green: 0.55, blue: 0.24)

    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .semibold, design: .serif) }
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
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
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
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.accent))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07)))
    }
}

/// The Bakdo mark: sound bars turning into a text cursor. Geometry matches design/app-icon.svg,
/// whose rounded square spans 100…924 of a 1024 canvas.
enum BrandMark {
    struct Bar { let x, y, width, height: CGFloat }

    static let bars: [Bar] = [
        Bar(x: 262, y: 412, width: 64, height: 200),
        Bar(x: 366, y: 322, width: 64, height: 380),
        Bar(x: 470, y: 372, width: 64, height: 280),
        Bar(x: 574, y: 437, width: 64, height: 150),
        // I-beam cursor: stem and the two caps.
        Bar(x: 688, y: 302, width: 26, height: 420),
        Bar(x: 664, y: 292, width: 74, height: 24),
        Bar(x: 664, y: 708, width: 74, height: 24),
    ]

    /// Bars mapped from icon space into a square of `side`, optionally zoomed so the glyph fills more of it.
    static func rects(side: CGFloat, glyphOnly: Bool = false) -> [CGRect] {
        let origin: CGFloat = glyphOnly ? 250 : 100
        let span: CGFloat = glyphOnly ? 500 : 824
        let scale = side / span
        return bars.map { CGRect(x: ($0.x - origin) * scale, y: ($0.y - origin - (glyphOnly ? 12 : 0)) * scale,
                                 width: $0.width * scale, height: $0.height * scale) }
    }

    /// Monochrome template image for the menu bar.
    static func menuBarImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSColor.black.setFill()
            for rect in rects(side: side, glyphOnly: true) {
                let radius = min(rect.width, rect.height) / 2
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bakdo"
        return image
    }
}

/// The app icon, drawn natively so it stays crisp at any size.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Theme.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay {
                Canvas { context, canvasSize in
                    for rect in BrandMark.rects(side: canvasSize.width) {
                        let radius = min(rect.width, rect.height) / 2
                        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(.white))
                    }
                }
            }
            .frame(width: size, height: size)
    }
}
