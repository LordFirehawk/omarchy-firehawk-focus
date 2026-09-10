import AppKit
import Combine
import SwiftUI

@main
struct FirehawkFocusMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class TrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = FocusEngine.shared
    private var statusItem: NSStatusItem!
    private var trayPanel: TrayPanel?
    private var clickOutsideMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupTrayPanel()
        observeEngine()

        if CommandLine.arguments.contains("--start") {
            engine.primaryAction()
        }

        // Show window on launch so user can see and test immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showTray()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        showTray()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTray()
        return true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusItemButton()
        }
    }

    private func setupTrayPanel() {
        let panel = TrayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 490),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = "Firehawk Focus"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(
            rootView: MainPopoverView(engine: engine, onClose: { [weak self] in
                self?.closeTray()
            })
        )
        self.trayPanel = panel

        engine.onRequestOpenPanel = { [weak self] in
            self?.showTray()
        }
    }

    private func observeEngine() {
        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Defer to next runloop tick so published properties have updated
                DispatchQueue.main.async {
                    self?.updateStatusItemButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemButton() {
        guard let button = statusItem.button else { return }

        // Configure symbol
        let symbolName: String = {
            switch engine.phase {
            case .focus: return "flame.fill"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "sparkles"
            }
        }()

        let imageConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Firehawk Focus")?.withSymbolConfiguration(imageConfig)
        button.imagePosition = .imageLeading

        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        func setMonospacedTitle(_ text: String) {
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            button.attributedTitle = attr
        }

        switch engine.status {
        case .ready:
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Firehawk Focus (\(engine.phase.title) ready)"
        case .running:
            setMonospacedTitle(engine.clockText)
            button.toolTip = "Firehawk Focus: \(engine.phase.title) (\(engine.clockText) remaining)"
        case .paused:
            setMonospacedTitle(engine.clockText + " ⏸")
            button.toolTip = "Firehawk Focus: Paused at \(engine.clockText)"
        case .complete:
            setMonospacedTitle("Done")
            button.toolTip = "Firehawk Focus: \(engine.phase.title) complete!"
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRightClick = (NSApp.currentEvent?.type == .rightMouseUp)
        if isRightClick {
            showContextMenu(sender)
        } else {
            toggleTray()
        }
    }

    private func toggleTray() {
        guard let panel = trayPanel else {
            showTray()
            return
        }
        if panel.isVisible {
            closeTray()
        } else {
            showTray()
        }
    }

    private func showTray() {
        guard let panel = trayPanel else { return }

        if !panel.isVisible {
            // Lock position in place when opening
            let targetOrigin = calculateTrayOrigin(panelSize: panel.frame.size)
            panel.setFrameOrigin(targetOrigin)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            startClickOutsideMonitor()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func closeTray() {
        stopClickOutsideMonitor()
        trayPanel?.orderOut(nil)
    }

    private func calculateTrayOrigin(panelSize: NSSize) -> NSPoint {
        let panelWidth = panelSize.width
        let panelHeight = panelSize.height

        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            let screen = NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
            return NSPoint(
                x: max(visible.origin.x + 12, visible.maxX - panelWidth - 16),
                y: max(visible.origin.y + 12, visible.maxY - panelHeight - 6)
            )
        }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        let buttonBounds = button.bounds
        let buttonScreenRect = buttonWindow.convertToScreen(buttonBounds)

        // Check if button is actually on screen and visible
        let isOffscreen = buttonScreenRect.origin.x < (screenFrame.origin.x - 10) ||
                          buttonScreenRect.origin.x > (screenFrame.maxX - 10)

        if isOffscreen {
            return NSPoint(
                x: max(visibleFrame.origin.x + 12, visibleFrame.maxX - panelWidth - 16),
                y: max(visibleFrame.origin.y + 12, visibleFrame.maxY - panelHeight - 6)
            )
        }

        // Center tray horizontally under the status item button
        var x = buttonScreenRect.midX - (panelWidth / 2.0)
        x = max(visibleFrame.origin.x + 10, min(x, visibleFrame.maxX - panelWidth - 10))

        // Position directly below menu bar
        let y = visibleFrame.maxY - panelHeight - 4

        return NSPoint(x: x, y: y)
    }

    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.trayPanel, panel.isVisible else { return }
            let mouseLocation = NSEvent.mouseLocation
            // If click is inside the panel, ignore
            if panel.frame.contains(mouseLocation) {
                return
            }
            // If click is on the status item button, let button target/action handle toggle
            if let button = self.statusItem?.button,
               let buttonWin = button.window,
               buttonWin.frame.contains(mouseLocation) {
                return
            }
            self.closeTray()
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        // Primary Action
        let primaryItem = NSMenuItem(
            title: engine.primaryButtonLabel,
            action: #selector(menuPrimaryAction),
            keyEquivalent: " "
        )
        primaryItem.target = self
        menu.addItem(primaryItem)

        // Switch Phase / Next Action
        let phaseSwitchTitle: String = {
            if engine.status == .complete {
                return engine.phase == .focus ? "Start Next Focus Session" : "Take Another Break"
            } else {
                return engine.phase == .focus ? "Take a Break" : "Start Focus"
            }
        }()
        let phaseSwitchItem = NSMenuItem(
            title: phaseSwitchTitle,
            action: #selector(menuPhaseSwitchAction),
            keyEquivalent: "b"
        )
        phaseSwitchItem.target = self
        menu.addItem(phaseSwitchItem)

        // Extend +5 min
        let extendItem = NSMenuItem(
            title: "+5 Minutes",
            action: #selector(menuExtendAction),
            keyEquivalent: "e"
        )
        extendItem.target = self
        menu.addItem(extendItem)

        menu.addItem(NSMenuItem.separator())

        // Open Full Panel
        let openItem = NSMenuItem(
            title: "Open Panel…",
            action: #selector(menuOpenPanelAction),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        // Reset
        let resetItem = NSMenuItem(
            title: "Reset Timer",
            action: #selector(menuResetAction),
            keyEquivalent: "r"
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Firehawk Focus",
            action: #selector(menuQuitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func menuPrimaryAction() { engine.primaryAction() }
    @objc private func menuPhaseSwitchAction() {
        if engine.status == .complete {
            if engine.phase == .focus {
                engine.startNextFocusSession()
            } else {
                engine.takeAnotherBreak()
            }
        } else {
            if engine.phase == .focus {
                engine.takeBreak()
            } else {
                engine.startFocusNow()
            }
        }
    }
    @objc private func menuExtendAction() { engine.extendTimer(minutes: 5) }
    @objc private func menuOpenPanelAction() { showTray() }
    @objc private func menuResetAction() { engine.resetTimer() }
    @objc private func menuQuitAction() { NSApplication.shared.terminate(nil) }
}
