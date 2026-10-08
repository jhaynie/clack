import AppKit
import ServiceManagement
import SwiftUI
import ClackAudio

final class AppState: ObservableObject {
    @Published var enabled: Bool { didSet {
        UserDefaults.standard.set(enabled, forKey: "enabled")
        if let audio { clack_set_enabled(audio.mixer, enabled) }
        onIconChanged?()
    } }
    @Published var volume: Double { didSet {
        UserDefaults.standard.set(volume, forKey: "volume")
        if let audio { clack_set_volume(audio.mixer, Float(volume)) }
    } }
    @Published var spatial: Double { didSet {
        UserDefaults.standard.set(spatial, forKey: "spatial")
        if let audio { clack_set_spatial(audio.mixer, Float(spatial)) }
    } }
    @Published var releases: Bool { didSet {
        UserDefaults.standard.set(releases, forKey: "releases")
        if let audio { clack_set_releases(audio.mixer, releases) }
    } }
    @Published var hasPermission = CGPreflightListenEventAccess()
    @Published var listening = false
    @Published var audioError: String?
    @Published var loginError: String?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var bufferMilliseconds: Double = 0
    @Published var previewing = false
    var onIconChanged: (() -> Void)?
    private(set) var audio: KeyboardAudio?
    private var monitor: KeyboardMonitor?
    private var timer: Timer?
    private var previewGeneration = 0

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["enabled": true, "volume": 0.65, "spatial": 0.8, "releases": true])
        enabled = defaults.bool(forKey: "enabled")
        volume = defaults.double(forKey: "volume")
        spatial = defaults.double(forKey: "spatial")
        releases = defaults.bool(forKey: "releases")
    }

    func start() {
        do {
            let audio = try KeyboardAudio()
            self.audio = audio
            clack_set_enabled(audio.mixer, enabled)
            clack_set_volume(audio.mixer, Float(volume))
            clack_set_spatial(audio.mixer, Float(spatial))
            clack_set_releases(audio.mixer, releases)
            audio.onStatus = { [weak self] message in
                self?.audioError = message
                self?.bufferMilliseconds = self?.audio?.bufferMilliseconds ?? 0
            }
            // Keep the input monitor available even if output is temporarily missing.
            let monitor = KeyboardMonitor(audio: audio)
            self.monitor = monitor
            monitor.onStatus = { [weak self] running in
                self?.listening = running
                self?.onIconChanged?()
            }
            do { try audio.start() } catch { audioError = error.localizedDescription }
            bufferMilliseconds = audio.bufferMilliseconds
            _ = monitor.start()
        } catch { audioError = error.localizedDescription }

        // The user requested startup launch. Register once, and honor future choices.
        if !UserDefaults.standard.bool(forKey: "configuredLogin") {
            setLoginEnabled(true)
            if loginError == nil { UserDefaults.standard.set(true, forKey: "configuredLogin") }
        }
        refreshLogin()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = CGPreflightListenEventAccess()
            if self.hasPermission != granted { self.hasPermission = granted }
            if granted && !self.listening { _ = self.monitor?.start() }
            if !granted && self.listening { self.monitor?.stop() }
            self.refreshLogin()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func woke() {
        audio?.restart()
        if hasPermission { _ = monitor?.start() }
    }

    func requestPermission() {
        _ = CGRequestListenEventAccess()
        openInputSettings()
    }

    func openInputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func retryAudio() {
        audioError = nil
        if let audio { audio.restart() } else { timer?.invalidate(); start() }
    }

    func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLoginEnabled(_ value: Bool) {
        do {
            if value {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            UserDefaults.standard.set(true, forKey: "configuredLogin")
        } catch { loginError = error.localizedDescription }
        refreshLogin()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func preview() {
        guard enabled, audioError == nil, let audio, !previewing else { return }
        previewing = true
        previewGeneration += 1
        let generation = previewGeneration
        let sequence: [UInt16] = [0,1,2,3,5,4,38,40,37,49,36]
        for (i, key) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.095) { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                clack_trigger(audio.mixer, key, false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.095 + 0.06) { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                clack_trigger(audio.mixer, key, true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.previewing = false }
    }

    func stop() {
        previewGeneration += 1
        timer?.invalidate()
        monitor?.stop()
        audio?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
