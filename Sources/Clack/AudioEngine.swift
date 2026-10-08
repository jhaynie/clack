import AVFoundation
import CoreAudio
import ClackAudio

/// The mixer is fixed at 48 kHz. AVAudioEngine converts at the hardware boundary,
/// so route changes never invalidate the pointer used by the input thread.
final class KeyboardAudio {
    let mixer: OpaquePointer
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var mixerWasFreed = false
    private var shuttingDown = false
    private var configurationObserver: NSObjectProtocol?
    private var originalBuffers: [AudioDeviceID: UInt32] = [:]
    private var requestedBuffers: [AudioDeviceID: UInt32] = [:]
    var onStatus: ((String?) -> Void)?
    private(set) var bufferMilliseconds: Double = 0

    init() throws {
        guard let mixer = clack_create(48_000) else { throw AudioError.message("Could not create the audio engine.") }
        self.mixer = mixer
        do {
            let names = (0..<5).map { "press-\($0)" } + [
                "press-space", "press-enter", "press-backspace", "release-generic",
                "release-space", "release-enter", "release-backspace"
            ]
            for (id, name) in names.enumerated() {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else {
                    throw AudioError.message("Missing keyboard recording: \(name). Rebuild the app bundle.")
                }
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)) else {
                    throw AudioError.message("Could not load \(name).")
                }
                try file.read(into: buffer)
                guard file.processingFormat.sampleRate == 48_000,
                      let pcm = buffer.floatChannelData,
                      clack_load(mixer, UInt32(id), pcm[0], buffer.frameLength) else {
                    throw AudioError.message("Invalid keyboard recording: \(name).")
                }
            }
        } catch {
            clack_destroy(mixer)
            mixerWasFreed = true
            throw error
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard list.count == 2, let l = list[0].mData, let r = list[1].mData else { return kAudio_ParamError }
            clack_render(mixer, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames)
            return noErr
        }
        self.source = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restart() }
    }

    func start() throws {
        requestSmallBuffer()
        engine.prepare()
        try engine.start()
    }

    func restart() {
        guard !shuttingDown else { return }
        engine.stop()
        do {
            try start()
            onStatus?(nil)
        } catch { onStatus?("Audio unavailable: \(error.localizedDescription). Use Retry Audio.") }
    }

    func stop() {
        shuttingDown = true
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        // Only restore a value if nobody else has changed it since our request.
        for (device, original) in originalBuffers {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var current: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr,
               current == requestedBuffers[device] {
                var value = original
                _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
            }
        }
        originalBuffers.removeAll()
        requestedBuffers.removeAll()
    }

    deinit {
        stop()
        if let source { engine.detach(source) }
        if !mixerWasFreed { clack_destroy(mixer) }
    }

    private func requestSmallBuffer() {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }
        address.mSelector = kAudioDevicePropertyBufferFrameSize
        var current: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else { return }
        var range = AudioValueRange()
        var rangeAddress = address; rangeAddress.mSelector = kAudioDevicePropertyBufferFrameSizeRange
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        if current > 128,
           AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &rangeSize, &range) == noErr {
            var preferred = UInt32(max(range.mMinimum, min(128, range.mMaximum)))
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &preferred) == noErr {
                if originalBuffers[device] == nil { originalBuffers[device] = current }
                requestedBuffers[device] = preferred
                _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current)
            }
        }
        var sampleRate: Double = 48_000
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        size = UInt32(MemoryLayout<Double>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &sampleRate)
        bufferMilliseconds = Double(current) / max(1, sampleRate) * 1000
    }
}

enum AudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
