import AppKit
import SwiftUI

/// A borderless, non-activating panel at the bottom of the screen that hosts the dictation pill.
/// It never takes focus, so the text field you're dictating into stays active.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let panel = OverlayPanel()
    private let controller = DictationController.shared

    init() {
        let host = NSHostingView(rootView: PillContainer())
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()
        observe()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    private func observe() {
        withObservationTracking {
            _ = controller.phase
            _ = controller.handsFree
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.phase == .recording { self.reposition() }
                // Only accept clicks while the hands-free controls are on screen.
                self.panel.ignoresMouseEvents = !(self.controller.phase == .recording && self.controller.handsFree)
                self.panel.orderFrontRegardless()
                self.observe()
            }
        }
    }

    /// Bottom-centre of whichever screen the pointer is on, just above the Dock.
    func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY - 4)
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Pill

private struct PillContainer: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            PillView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
    }
}

/// Spell light: the icon's gold quill, a warm amber and a touch of night-sky violet.
private enum PillPalette {
    static let gold = Color(red: 1.00, green: 0.86, blue: 0.50)
    static let amber = Color(red: 0.96, green: 0.65, blue: 0.22)
    static let violet = Color(red: 0.62, green: 0.46, blue: 1.00)
    static let ink = Color(red: 0.07, green: 0.055, blue: 0.14)
    static let ring: [Color] = [gold, violet, amber, gold]
    static let wave = Gradient(colors: [violet, gold, amber, gold, violet])
}

struct PillView: View {
    @State private var controller = DictationController.shared
    @State private var settings = AppSettings.shared

    private enum Mode: Equatable {
        case hidden, idle, recording, handsFree, transcribing, fixing, done(String), message(String, Bool)

        var isLive: Bool {
            switch self {
            case .recording, .handsFree, .transcribing, .fixing: return true
            default: return false
            }
        }
    }

    private var mode: Mode {
        switch controller.phase {
        case .recording:
            guard controller.committed else { return restingMode }
            return controller.handsFree ? .handsFree : .recording
        case .transcribing:
            return .transcribing
        case .fixing:
            return .fixing
        case .message(let text, let isError):
            return .message(text, isError)
        case .idle:
            if let done = controller.doneFlash { return .done(done) }
            return restingMode
        }
    }

    private var restingMode: Mode { settings.showIdlePill ? .idle : .hidden }

    private var size: CGSize {
        switch mode {
        case .hidden: return CGSize(width: 20, height: 6)
        case .idle: return CGSize(width: 38, height: 7)
        case .recording: return CGSize(width: 184, height: 44)
        case .handsFree: return CGSize(width: 262, height: 44)
        case .transcribing: return CGSize(width: 168, height: 40)
        case .fixing: return CGSize(width: 150, height: 40)
        case .done(let text): return CGSize(width: CGFloat(text.count) * 7.4 + 62, height: 36)
        case .message(let text, _): return CGSize(width: min(320, CGFloat(text.count) * 7.2 + 56), height: 36)
        }
    }

    var body: some View {
        ZStack {
            if mode.isLive {
                LiveChrome(energy: energy, fast: mode == .transcribing || mode == .fixing)
                    .transition(.opacity)
            } else {
                StaticChrome(idle: mode == .idle, success: isDone)
                    .transition(.opacity)
            }
            content
                .transition(.blurReplace.combined(with: .scale(0.9)))
                .id(contentID)
        }
        .frame(width: size.width, height: size.height)
        .opacity(mode == .hidden ? 0 : 1)
        .scaleEffect(mode == .hidden ? 0.5 : 1, anchor: .bottom)
        .animation(.spring(response: 0.42, dampingFraction: 0.66), value: mode)
    }

    private var isDone: Bool {
        if case .done = mode { return true }
        return false
    }

    /// Changes only when the kind of content changes, so the waveform isn't torn down on every level update.
    private var contentID: String {
        switch mode {
        case .hidden: return "hidden"
        case .idle: return "idle"
        case .recording: return "rec"
        case .handsFree: return "hands"
        case .transcribing: return "writing"
        case .fixing: return "fixing"
        case .done: return "done"
        case .message: return "message"
        }
    }

    /// Recent loudness, 0...1, from the last few level samples.
    private var energy: Double {
        let recent = controller.levels.suffix(3)
        guard !recent.isEmpty, controller.phase == .recording else { return 0 }
        return Double(recent.reduce(0, +)) / Double(recent.count)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .hidden, .idle:
            Color.clear
        case .recording:
            HStack(spacing: 10) {
                LiveDot()
                LiveWave(levels: controller.levels, barCount: 22, maxHeight: 30)
                    .overlay { RisingSparkles(energy: energy).allowsHitTesting(false) }
            }
            .padding(.horizontal, 16)
        case .handsFree:
            HStack(spacing: 10) {
                PillButton(symbol: "xmark", tint: .white.opacity(0.14)) { controller.cancelFromUI() }
                LiveDot()
                LiveWave(levels: controller.levels, barCount: 18, maxHeight: 28)
                    .overlay { RisingSparkles(energy: energy).allowsHitTesting(false) }
                ElapsedTime(since: controller.recordingStartedAt)
                PillButton(symbol: "stop.fill", tint: PillPalette.amber) { controller.toggleHandsFree() }
            }
            .padding(.horizontal, 8)
        case .transcribing:
            HStack(spacing: 8) {
                SparkleIcon()
                Text("Inscribing")
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                    .foregroundStyle(PillPalette.gold)
                ThinkingWave()
            }
        case .fixing:
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PillPalette.gold)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Reparo")
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(PillPalette.gold)
                ThinkingWave()
            }
        case .done(let text):
            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PillPalette.gold)
                    .symbolEffect(.bounce, value: text)
                Text(text)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(PillPalette.gold)
            }
        case .message(let text, let isError):
            HStack(spacing: 7) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? Color.orange : Color.white.opacity(0.7))
                Text(text)
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Chrome

/// Dark glass capsule with a light that orbits the border and an aura that swells with your voice.
private struct LiveChrome: View {
    let energy: Double
    let fast: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * (fast ? 220 : 90)).truncatingRemainder(dividingBy: 360))
            let ring = AngularGradient(colors: PillPalette.ring, center: .center, angle: angle)
            let breathe = 0.5 + 0.5 * sin(t * 2.2)
            ZStack {
                Capsule()
                    .fill(ring)
                    .blur(radius: 16)
                    .opacity(0.28 + 0.12 * breathe + energy * 0.55)
                    .scaleEffect(x: 1.02 + energy * 0.10, y: 1.05 + energy * 0.35)
                Capsule()
                    .fill(PillPalette.ink.opacity(0.95))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
                Capsule()
                    .strokeBorder(ring, lineWidth: 1.4)
                    .opacity(0.95)
            }
        }
    }
}

private struct StaticChrome: View {
    let idle: Bool
    let success: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(idle ? Color.black.opacity(0.5) : PillPalette.ink.opacity(0.95))
            Capsule()
                .strokeBorder(
                    success
                        ? AnyShapeStyle(LinearGradient(colors: [PillPalette.gold, PillPalette.amber], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(LinearGradient(colors: PillPalette.ring, startPoint: .leading, endPoint: .trailing)
                            .opacity(idle ? 0.55 : 0.6)),
                    lineWidth: idle ? 1 : 1.2
                )
        }
        .shadow(color: .black.opacity(idle ? 0.15 : 0.35), radius: idle ? 3 : 10, y: 3)
    }
}

// MARK: - Pieces

/// Gradient bars driven by the microphone. Newest audio sits in the middle and ripples outwards;
/// each bar also wobbles on its own so the wave feels alive even on a steady voice or in silence.
private struct LiveWave: View {
    let levels: [Float]
    let barCount: Int
    let maxHeight: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let barWidth: CGFloat = 3
                let spacing = (size.width - barWidth * CGFloat(barCount)) / CGFloat(max(1, barCount - 1))
                let center = Double(barCount - 1) / 2
                var path = Path()
                for i in 0..<barCount {
                    let distance = abs(Double(i) - center)
                    let sampleIndex = max(0, levels.count - 1 - Int(distance * 0.9))
                    let level = levels.isEmpty ? 0 : Double(levels[sampleIndex])
                    let envelope = exp(-pow(distance / (center * 1.05 + 0.5), 2))
                    let wobble = 0.74 + 0.26 * sin(t * 9 + Double(i) * 0.9) * cos(t * 3.7 + Double(i) * 1.7)
                    let idleRipple = 0.5 + 0.5 * sin(t * 3 - Double(i) * 0.45)
                    let h = 3 + idleRipple * 2.5 + (Double(maxHeight) - 6) * min(1, level * 1.8) * envelope * wobble
                    let height = min(size.height, CGFloat(h))
                    let x = CGFloat(i) * (barWidth + spacing)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
                }
                gc.fill(path, with: .linearGradient(PillPalette.wave, startPoint: .zero,
                                                    endPoint: CGPoint(x: size.width, y: 0)))
            }
        }
        .frame(height: maxHeight)
    }
}

/// Little four-point stars drifting up off the waveform, like sparks from a wand.
/// More of them, and brighter, the louder you speak.
private struct RisingSparkles: View {
    let energy: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                for i in 0..<14 {
                    let seed = Double(i) * 0.6180339887
                    let speed = 0.45 + (seed * 7).truncatingRemainder(dividingBy: 1) * 0.5
                    let phase = (t * speed + seed).truncatingRemainder(dividingBy: 1)
                    let visibility = sin(.pi * phase) * min(1, 0.25 + energy * 1.6)
                    guard visibility > 0.05 else { continue }
                    let x = (seed * 13).truncatingRemainder(dividingBy: 1) * size.width
                        + sin(t * 2 + Double(i)) * 3
                    let y = size.height * (1.1 - phase * 1.7)
                    let r = (1.2 + (1 - phase) * 2.6) * (0.7 + energy * 0.8)
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y - r * 1.6))
                    star.addQuadCurve(to: CGPoint(x: x + r * 1.6, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y + r * 1.6), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x - r * 1.6, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y - r * 1.6), control: CGPoint(x: x, y: y))
                    gc.fill(star, with: .color(Color(red: 1, green: 0.93, blue: 0.70).opacity(visibility)))
                }
            }
        }
        .padding(.vertical, -12)
    }
}

/// While the models work: a travelling wave of dots in the brand gradient.
private struct ThinkingWave: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let count = 5
                let dot: CGFloat = 5
                let spacing = (size.width - dot * CGFloat(count)) / CGFloat(count - 1)
                var path = Path()
                for i in 0..<count {
                    let phase = sin(t * 7 - Double(i) * 0.8)
                    let height = dot + CGFloat(max(0, phase)) * 9
                    let x = CGFloat(i) * (dot + spacing)
                    path.addRoundedRect(in: CGRect(x: x, y: (size.height - height) / 2, width: dot, height: height),
                                        cornerSize: CGSize(width: dot / 2, height: dot / 2))
                }
                gc.fill(path, with: .linearGradient(PillPalette.wave, startPoint: .zero,
                                                    endPoint: CGPoint(x: size.width, y: 0)))
            }
            .frame(width: 52, height: 20)
        }
    }
}

private struct SparkleIcon: View {
    var body: some View {
        Image(systemName: "wand.and.stars")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PillPalette.gold)
            .symbolEffect(.variableColor.iterative, options: .repeating)
    }
}

/// Recording indicator: a dot with a ring that keeps expanding and fading.
private struct LiveDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let p = (t * 0.9).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle()
                    .stroke(PillPalette.gold, lineWidth: 1.5)
                    .frame(width: 7 + 10 * p, height: 7 + 10 * p)
                    .opacity(1 - p)
                Circle()
                    .fill(RadialGradient(colors: [.white, PillPalette.gold], center: .center, startRadius: 0, endRadius: 4))
                    .frame(width: 7, height: 7)
                    .shadow(color: PillPalette.gold, radius: 4)
            }
            .frame(width: 18, height: 18)
        }
    }
}

private struct ElapsedTime: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(since ?? context.date))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .contentTransition(.numericText())
        }
    }
}

private struct PillButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint))
        }
        .buttonStyle(.plain)
    }
}
