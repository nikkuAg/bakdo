import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Captures microphone audio and converts it to 16 kHz mono Float32, the format Whisper expects.
final class AudioRecorder: @unchecked Sendable {
    /// Called on the main thread with a 0...1 loudness value roughly 20 times a second.
    var onLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Double(WhisperEngine.sampleRate),
                                             channels: 1, interleaved: false)!

    var isRunning: Bool { engine?.isRunning ?? false }

    func start(deviceUID: String) throws {
        stopEngine()
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if !deviceUID.isEmpty, let device = Self.inputDevices().first(where: { $0.uid == deviceUID }),
           let unit = input.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "Bakdo", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone found"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "Bakdo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format"])
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 20)

        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.reportLevel(buffer)

            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let data = out.floatChannelData?[0], out.frameLength > 0 else { return }
            let chunk = UnsafeBufferPointer(start: data, count: Int(out.frameLength))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Stops recording and returns everything captured.
    func stop() -> [Float] {
        stopEngine()
        return lock.withLock {
            let captured = samples
            samples.removeAll()
            return captured
        }
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        // Map roughly -50 dB...-10 dB onto 0...1.
        let db = 20 * log10(max(rms, 1e-6))
        let level = max(0, min(1, (db + 50) / 40))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    // MARK: - Devices

    static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streamsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                            mScope: kAudioDevicePropertyScopeInput,
                                                            mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            guard let name = stringProperty(id, kAudioObjectPropertyName),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

enum AudioProcessing {
    /// Trims leading/trailing silence and boosts quiet recordings. Returns nil when the clip
    /// contains no speech, which is what stops Whisper from hallucinating text out of silence.
    static func prepare(_ samples: [Float]) -> [Float]? {
        let frame = WhisperEngine.sampleRate * 30 / 1000
        guard samples.count >= frame * 5 else { return nil }

        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frame)
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            energies.append(sqrt(sum / Float(frame)))
            i += frame
        }

        let sorted = energies.sorted()
        let noiseFloor = sorted[sorted.count / 10]
        let peak = sorted.last ?? 0
        guard peak > 0.003 else { return nil }

        let threshold = max(0.0025, min(noiseFloor * 3, peak * 0.25))
        let voiced = energies.indices.filter { energies[$0] > threshold }
        guard voiced.count >= 4, let first = voiced.first, let last = voiced.last else { return nil }

        let startFrame = max(0, first - 8)
        let endFrame = min(energies.count, last + 12)
        var trimmed = Array(samples[(startFrame * frame)..<min(samples.count, endFrame * frame)])

        // Normalise quiet microphones toward a healthy peak, but never amplify more than 8x.
        let absPeak = trimmed.reduce(0) { max($0, abs($1)) }
        if absPeak > 0, absPeak < 0.5 {
            let gain = min(8, 0.7 / absPeak)
            for k in trimmed.indices { trimmed[k] *= gain }
        }
        return trimmed
    }
}
