import AVFoundation
import HalodeckCore
import os

/// Short sounds for each volume/brightness step; the pitch follows the level.
/// Synthesised styles are generated at the right pitch; system sounds are pitch-shifted.
@MainActor
enum SoundTicks {
    private static let engine = AVAudioEngine()
    private static let synthPlayer = AVAudioPlayerNode()
    private static let filePlayer = AVAudioPlayerNode()
    private static let pitch = AVAudioUnitTimePitch()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private static var wired = false
    private static var fileBuffers: [SoundStyle: AVAudioPCMBuffer] = [:]
    nonisolated private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "sound")
    /// A running engine keeps the output device (and Bluetooth headphones) awake: it is paused
    /// after this long without a tick and started again by the next one.
    private static let idleTime: Duration = .seconds(2)
    private static var idlePause: Task<Void, Never>?

    static func play(_ style: SoundStyle, level: Double?) {
        guard start() else { return }
        pauseWhenIdle()
        switch style {
        case .marimba, .softClick, .glass:
            guard let buffer = synthesize(style, frequency: SoundPitch.frequency(forLevel: level)) else { return }
            synthPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            if !synthPlayer.isPlaying { synthPlayer.play() }
        case .tink, .pop, .bottle, .morse:
            guard let buffer = systemSound(style) else { return }
            pitch.pitch = Float(SoundPitch.cents(forLevel: level))
            filePlayer.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
            if !filePlayer.isPlaying { filePlayer.play() }
        }
    }

    static func preview(_ style: SoundStyle) {
        for (i, level) in [0.0, 0.25, 0.5, 0.75, 1.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { play(style, level: level) }
        }
    }

    /// Builds the graph once and (re)starts the engine whenever it isn't running: macOS stops it when
    /// the output device changes (headphones, AirPods), and playing on a stopped engine raises an exception.
    private static func start() -> Bool {
        if !wired {
            engine.attach(synthPlayer)
            engine.attach(filePlayer)
            engine.attach(pitch)
            engine.connect(synthPlayer, to: engine.mainMixerNode, format: format)
            engine.connect(filePlayer, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
            wired = true
        }
        if engine.isRunning { return true }
        do {
            try engine.start()
        } catch {
            log.error("audio engine didn't start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return engine.isRunning
    }

    private static func pauseWhenIdle() {
        idlePause?.cancel()
        idlePause = Task { @MainActor in
            try? await Task.sleep(for: idleTime)
            guard !Task.isCancelled else { return }
            engine.pause()
            idlePause = nil
        }
    }

    private static func synthesize(_ style: SoundStyle, frequency f: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length: Double = style == .softClick ? 0.03 : style == .marimba ? 0.18 : 0.06
        let frames = AVAudioFrameCount(rate * length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        var noise = SystemRandomNumberGenerator()
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let value: Double
            switch style {
            case .marimba:
                // Warm wooden note an octave lower: fundamental plus the bright 4th partial that dies fast.
                let base = f / 2
                let attack = min(1, t / 0.002)
                value = 0.26 * attack * (exp(-t / 0.07) * sin(2 * .pi * base * t)
                                         + 0.35 * exp(-t / 0.012) * sin(2 * .pi * base * 4 * t))
            case .softClick:
                let n = Double.random(in: -1...1, using: &noise)
                value = 0.22 * (exp(-t / 0.004) * sin(2 * .pi * f * 1.5 * t) + 0.25 * exp(-t / 0.002) * n)
            default:   // glass
                let attack = min(1, t / 0.003)
                value = 0.18 * attack * exp(-t / 0.018) * (sin(2 * .pi * f * t) + 0.25 * sin(4 * .pi * f * t))
            }
            channels[0][i] = Float(value)
            channels[1][i] = Float(value)
        }
        return buffer
    }

    private static func systemSound(_ style: SoundStyle) -> AVAudioPCMBuffer? {
        if let cached = fileBuffers[style] { return cached }
        let name = style.title   // Tink, Pop, Bottle, Morse
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        guard let file = try? AVAudioFile(forReading: url),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else { return nil }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        guard let output = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024)
        else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return source
        }
        guard error == nil else { return nil }
        fileBuffers[style] = output
        return output
    }
}
