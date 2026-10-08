import AppKit
import ClackAudio

/// A dedicated run loop keeps keyboard input independent of menu rendering.
/// Listen-only: no event modification and no reading characters or saving input.
final class KeyboardMonitor {
    private let audio: KeyboardAudio
    private var mixer: OpaquePointer { audio.mixer }
    private var thread: Thread?
    private let lifecycle = NSLock()
    private var runLoop: CFRunLoop?
    private var stopping = false
    // Accessed only on the input thread.
    private var tap: CFMachPort?
    private var pressed = [Bool](repeating: false, count: 256)
    private var sounded = [Bool](repeating: false, count: 256)
    var onStatus: ((Bool) -> Void)?

    init(audio: KeyboardAudio) { self.audio = audio }

    static func makeTap(callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        return CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: userInfo)
    }

    @discardableResult func start() -> Bool {
        guard CGPreflightListenEventAccess() else { return false }
        lifecycle.lock()
        guard thread == nil else { lifecycle.unlock(); return true }
        stopping = false
        let worker = Thread { [weak self] in self?.run() }
        worker.name = "Clack Keyboard Input"
        worker.qualityOfService = .userInteractive
        thread = worker
        lifecycle.unlock()
        worker.start()
        return true
    }

    func stop() {
        lifecycle.lock()
        stopping = true
        if let runLoop { CFRunLoopStop(runLoop) }
        lifecycle.unlock()
    }

    private func run() {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        tap = Self.makeTap(callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.receive(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: pointer)
        guard let tap else { finish(); report(false); return }
        let loop = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lifecycle.lock()
        runLoop = loop
        let shouldRun = !stopping
        lifecycle.unlock()
        report(shouldRun)
        if shouldRun { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        pressed = [Bool](repeating: false, count: 256)
        sounded = [Bool](repeating: false, count: 256)
        finish()
        report(false)
    }

    private func finish() {
        lifecycle.lock()
        runLoop = nil; thread = nil
        lifecycle.unlock()
    }

    private func report(_ running: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(running) }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pressed = [Bool](repeating: false, count: 256)
            sounded = [Bool](repeating: false, count: 256)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard key >= 0 && key < pressed.count else { return }
        if type == .keyDown {
            // A held key has one physical downstroke, regardless of OS autorepeat.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !pressed[key] else { return }
            pressed[key] = true
            if clack_should_sound(UInt16(key), event.flags.rawValue) {
                sounded[key] = clack_trigger(mixer, UInt16(key), false)
            }
        } else if type == .keyUp {
            guard pressed[key] else { return }
            pressed[key] = false
            // Pair releases with sounded presses, even if Command was released first.
            if sounded[key] && clack_should_sound(UInt16(key), event.flags.rawValue) {
                clack_trigger(mixer, UInt16(key), true)
            }
            sounded[key] = false
        }
    }
}
