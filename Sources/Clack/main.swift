import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--check-input"), arguments.count > index + 1 {
            let tap = KeyboardMonitor.makeTap(callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
            let report: [String: Any] = ["permissionGranted": CGPreflightListenEventAccess(), "eventTapCreated": tap != nil]
            if let tap { CFMachPortInvalidate(tap) }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: arguments[index + 1]))
            }
            NSApp.terminate(nil)
            return
        }
        // Multiple launches must not double every keystroke.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        state.onIconChanged = { [weak self] in self?.updateIcon() }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(state: state))
        state.start()
        updateIcon()
        if !state.hasPermission || state.audioError != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { state.stop() }

    private func updateIcon() {
        let image = NSImage(systemSymbolName: state.enabled ? "keyboard" : "pause.circle", accessibilityDescription: "Clack")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = state.enabled ? "Clack — Keyboard sounds on" : "Clack — Paused"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            let toggle = menu.addItem(withTitle: state.enabled ? "Pause Clack" : "Enable Clack",
                                     action: #selector(toggleEnabled), keyEquivalent: "")
            toggle.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit Clack", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    @objc private func toggleEnabled() { state.enabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Graceful shutdown also restores output buffering when the installer updates us.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { app.terminate(nil) }
termination.resume()
app.run()
