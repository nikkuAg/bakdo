import AppKit
import SwiftUI

/// Debug aid: `Bakdo --snapshot <dir>` renders each screen to PNG, in light and dark mode,
/// with sample history. Nothing is written to the user's settings or history.
@MainActor
enum Snapshot {
    static func render(to directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let now = Date()
        let samples: [(String, String?, Double)] = [
            ("Yaar, aaj ki meeting bahut lambi thi. Main thoda tired hoon. Kal baat karte hain.", "Slack", -300),
            ("Hey, can you send me the quarterly report by tomorrow evening? I need to review it before the client meeting.", "Gmail", -3600),
            ("Please mujhe vah document bhej do. Main evening tak review kar doonga.", "WhatsApp", -7200),
            ("I think we should push the launch to next Thursday, because the onboarding flow still has a few bugs.", "Notion", -90_000),
        ]
        HistoryStore.shared.loadForPreview(samples.map { text, app, offset in
            Transcript(date: now.addingTimeInterval(offset), text: text, rawText: text,
                       audioSeconds: Double(TextPostProcessor.wordCount(text)) / 2.4, processingSeconds: 1.02,
                       language: "en", appName: app)
        })

        let views: [(String, AnyView)] = [
            ("home", AnyView(MainView(page: .home))),
            ("dictionary", AnyView(MainView(page: .dictionary))),
            ("voice", AnyView(MainView(page: .voice))),
            ("settings", AnyView(MainView(page: .settings))),
            ("onboarding-0", AnyView(OnboardingView(step: 0))),
            ("onboarding-1", AnyView(OnboardingView(step: 1))),
            ("onboarding-2", AnyView(OnboardingView(step: 2))),
            ("onboarding-3", AnyView(OnboardingView(step: 3))),
        ]
        let onboarded = AppSettings.shared.hasCompletedOnboarding
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view) in views {
                AppSettings.shared.hasCompletedOnboarding = !name.hasPrefix("onboarding")
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: 40, y: 40))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                let suffix = appearance == .aqua ? "light" : "dark"
                let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(suffix).png").path
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
                try? capture.run()
                capture.waitUntilExit()
                window.orderOut(nil)
            }
        }
        AppSettings.shared.hasCompletedOnboarding = onboarded
        renderPills(to: directory)
        // Menu bar glyph at 8x so its shape can be inspected.
        let glyph = BrandMark.menuBarImage()
        let side = 144
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            glyph.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("menubar-glyph.png"))
        }
        print("snapshots written to \(directory)")
    }

    /// Renders each state of the dictation pill over a busy backdrop, to judge glow and contrast.
    static func renderPills(to directory: String) {
        let controller = DictationController.shared
        func voice(_ loudness: Float) -> [Float] {
            (0..<28).map { i in max(0, min(1, loudness * (0.55 + 0.45 * Float(sin(Double(i) * 1.7))))) }
        }
        let states: [(String, () -> Void)] = [
            ("pill-1-listening-quiet", { controller.debugShow(phase: .recording, levels: voice(0.15)) }),
            ("pill-2-listening-talking", { controller.debugShow(phase: .recording, levels: voice(0.55)) }),
            ("pill-3-listening-loud", { controller.debugShow(phase: .recording, levels: voice(0.95)) }),
            ("pill-4-handsfree", { controller.debugShow(phase: .recording, handsFree: true, levels: voice(0.5)) }),
            ("pill-5-writing", { controller.debugShow(phase: .transcribing) }),
            ("pill-6-done", { controller.debugShow(phase: .idle, done: "Typed 12 words") }),
            ("pill-7-idle", { controller.debugShow(phase: .idle) }),
        ]
        for (name, apply) in states {
            apply()
            let backdrop = ZStack {
                LinearGradient(colors: [Color(red: 0.93, green: 0.94, blue: 0.97), Color(red: 0.80, green: 0.84, blue: 0.92)],
                               startPoint: .top, endPoint: .bottom)
                PillView().padding(.bottom, 16).frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: 380, height: 120)
            let renderer = ImageRenderer(content: backdrop)
            renderer.scale = 3
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }
}
