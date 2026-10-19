import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private let controller = DictationController.shared
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMainMenu()
        applyDockPreference()
        buildStatusItem()
        controller.start()
        overlay = OverlayController()

        // Open the window on first run or when something still needs setting up; otherwise
        // stay out of the way in the menu bar like other dictation tools.
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?
            .enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin || !settings.hasCompletedOnboarding || !Permissions.shared.allGranted {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applyDockPreference() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    // MARK: - Main window

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Inscribo"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 860, height: 580)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let host = NSHostingView(rootView: MainView())
            // The window owns its size; SwiftUI content must never resize it between pages or onboarding steps.
            host.sizingOptions = []
            window.contentView = host
            window.center()
            window.setFrameAutosaveName("InscriboMainWindow")
            mainWindow = window
        }
        if !settings.showInDock { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Menu-bar-only mode: drop the Dock icon again once the window is gone.
        if !settings.showInDock {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = BrandMark.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        switch controller.engineState {
        case .ready: status = "Ready — hold \(settings.triggerKey.shortLabel) to dictate"
        case .loading: status = "Loading speech model…"
        case .missing: status = "Downloading speech model…"
        case .failed(let reason): status = reason
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !Permissions.shared.allGranted {
            menu.addItem(withTitle: "⚠︎ Permissions needed…", action: #selector(openApp), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())

        let toggleTitle = controller.phase == .recording ? "Stop Dictation" : "Start Hands-free Dictation"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleDictation), keyEquivalent: "").target = self
        if settings.fixShortcutEnabled {
            menu.addItem(withTitle: "Fix Selected Text  \(settings.fixShortcut.display)", action: #selector(fixSelection), keyEquivalent: "").target = self
        }
        let paste = menu.addItem(withTitle: "Paste Last Transcript", action: #selector(pasteLast), keyEquivalent: "")
        paste.target = self
        paste.isEnabled = !HistoryStore.shared.items.isEmpty
        let copy = menu.addItem(withTitle: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = !HistoryStore.shared.items.isEmpty

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Inscribo", action: #selector(openApp), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Quit Inscribo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openApp() { showMainWindow() }
    @objc private func toggleDictation() { controller.toggleHandsFree() }
    @objc private func fixSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { DictationController.shared.fixSelection() }
    }
    @objc private func pasteLast() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { DictationController.shared.pasteLastTranscript() }
    }
    @objc private func copyLast() {
        if let text = HistoryStore.shared.items.first?.text { TextInserter.copyToClipboard(text) }
    }

    // MARK: - App menu

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Inscribo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Inscribo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Inscribo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
