import AppKit
import Combine
import SwiftUI

@main
struct SpotiTextMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 220),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 300, height: 120)
    }

    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let state = AppState()
    private var panel: OverlayPanel!
    private var statusItem: NSStatusItem!
    private let bridge = WindowBridge()
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverlayPanel()
        panel.delegate = self
        bridge.window = panel
        let hostingView = FirstMouseHostingView(rootView: OverlayView(state: state, window: bridge))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        if !panel.setFrameUsingName("OverlayFrame"), let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 60))
        }
        panel.setFrameAutosaveName("OverlayFrame")

        applyMinimumSize()
        state.$locked
            .sink { [weak self] locked in self?.panel.ignoresMouseEvents = locked }
            .store(in: &subscriptions)
        state.$showSettings
            .sink { [weak self] open in
                self?.panel.allowsKey = open
                if open { NSApp.activate() }
            }
            .store(in: &subscriptions)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "SpotiText")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        state.$userHidden
            .sink { [weak self] hidden in
                if hidden { self?.panel.orderOut(nil) } else { self?.panel.orderFrontRegardless() }
            }
            .store(in: &subscriptions)
        state.start()
    }

    private func applyMinimumSize() {
        let size = OverlayView.minimumSize
        bridge.minimumSize = size
        panel.minSize = size
        panel.contentMinSize = size
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, bridge.minimumSize.width),
               height: max(frameSize.height, bridge.minimumSize.height))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, panel.isVisible ? "Hide Overlay" : "Show Overlay", #selector(toggleOverlay), "l")
        add(menu, "Lock (Click-Through)", #selector(toggleLock), "k").state = state.locked ? .on : .off
        add(menu, "Settings…", #selector(openSettings), ",")
        menu.addItem(.separator())
        add(menu, "Quit", #selector(quit), "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleOverlay() { state.userHidden = panel.isVisible }

    @objc private func toggleLock() { state.locked.toggle() }

    @objc private func openSettings() {
        state.locked = false
        state.userHidden = false
        state.showSettings = true
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
