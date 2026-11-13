import Foundation
import AVFoundation
import KitchenCore

/// Dźwięki piaskownicy — syntezowane w locie, zero plików w bundlu.
///
/// Po co proceduralnie: apka ma działać offline i nie wozić dwudziestu
/// plików WAV, a każdy dźwięk to kilkadziesiąt linii opisu fizyki
/// (szum + obwiednia + filtr), nie nagranie do licencjonowania.
///
/// Wszystko liczone raz przy pierwszym użyciu i trzymane w pamięci.
@MainActor
final class SandboxAudio {
    static let shared = SandboxAudio()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var cache: [SandboxSound: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat

    /// Ile jednoczesnych głosów — tyle, żeby szybkie stawianie serii
    /// nie ucinało poprzedniego dźwięku.
    private let voiceCount = 6

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        for _ in 0..<voiceCount {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: mixer, format: format)
            players.append(p)
        }

        try? engine.start()
    }

    /// Odtwarza dźwięk wstawienia. `volume` 0…1.
    func play(_ sound: SandboxSound, volume: Double = 0.7) {
        guard sound != .none, volume > 0.01 else { return }
        if !engine.isRunning { try? engine.start() }

        let buffer = buffer(for: sound)
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count

        player.stop()
        player.volume = Float(max(0, min(1, volume)))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    /// Pstryknięcie palcami — osobne, bo to sygnał „wstawiam", nie dźwięk obiektu.
    func snap(volume: Double = 0.8) {
        play(.snap, volume: volume)
    }

    // MARK: - synteza

    private func buffer(for sound: SandboxSound) -> AVAudioPCMBuffer {
        if let cached = cache[sound] { return cached }
        let b = synthesize(sound)
        cache[sound] = b
        return b
    }

    private func synthesize(_ sound: SandboxSound) -> AVAudioPCMBuffer {
        let spec = spec(for: sound)
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(max(1, spec.duration * sr))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]

        // deterministyczny szum — ten sam dźwięk przy każdym uruchomieniu
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let x = Double((seed >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
            return x * 2 - 1
        }

        // filtr jednobiegunowy dolnoprzepustowy — do „drewna" i „stuku"
        var lp = 0.0
        // filtr górnoprzepustowy — do „liści" i „szmeru"
        var hpPrev = 0.0
        var hpOut = 0.0

        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let n = Double(i) / Double(frames)   // 0…1 pozycja w obwiedni

            var s = 0.0

            // --- część tonalna ---
            if spec.tone > 0 {
                let f = spec.startFreq * pow(spec.endFreq / spec.startFreq, n)
                s += sin(2 * .pi * f * t) * spec.tone * exp(-spec.toneDecay * n)
                // druga harmoniczna — „metal" i „kamień" brzmią pełniej
                if spec.harmonic > 0 {
                    s += sin(2 * .pi * f * 2.01 * t) * spec.tone * spec.harmonic * exp(-spec.toneDecay * 1.4 * n)
                }
            }

            // --- część szumowa ---
            if spec.noise > 0 {
                let raw = noise()
                if spec.lowpass > 0 {
                    lp += (raw - lp) * spec.lowpass
                    s += lp * spec.noise * exp(-spec.noiseDecay * n)
                } else if spec.highpass > 0 {
                    hpOut = spec.highpass * (hpOut + raw - hpPrev)
                    hpPrev = raw
                    s += hpOut * spec.noise * exp(-spec.noiseDecay * n)
                } else {
                    s += raw * spec.noise * exp(-spec.noiseDecay * n)
                }
            }

            // --- transient (atak) ---
            if spec.transient > 0, n < 0.06 {
                s += noise() * spec.transient * (1 - n / 0.06)
            }

            // --- obwiednia całkowita: szybki atak, wykładnicze wybrzmienie ---
            let attack = min(1.0, t / max(0.001, spec.attack))
            let release = exp(-spec.release * n)
            out[i] = Float(s * attack * release * 0.55)
        }

        return buffer
    }

    private struct Spec {
        var duration: Double = 0.18
        var startFreq: Double = 800
        var endFreq: Double = 800
        var tone: Double = 0.5
        var toneDecay: Double = 2.0
        var harmonic: Double = 0
        var noise: Double = 0.3
        var noiseDecay: Double = 3.0
        var lowpass: Double = 0
        var highpass: Double = 0
        var transient: Double = 0
        var attack: Double = 0.002
        var release: Double = 3.0
    }

    private func spec(for sound: SandboxSound) -> Spec {
        switch sound {
        case .none:
            return Spec(duration: 0.01, tone: 0, noise: 0)

        case .snap:
            // Pstryknięcie palcami: bardzo krótki trzask + suchy klik.
            // Najważniejsze, żeby był ostry — reszta to ogon.
            return Spec(duration: 0.13, startFreq: 2400, endFreq: 1500,
                        tone: 0.35, toneDecay: 9, harmonic: 0.4,
                        noise: 0.85, noiseDecay: 11, highpass: 0.55,
                        transient: 1.0, attack: 0.0008, release: 7)

        case .pop:
            return Spec(duration: 0.09, startFreq: 900, endFreq: 380,
                        tone: 0.7, toneDecay: 5, noise: 0.08, noiseDecay: 8,
                        attack: 0.001, release: 5)

        case .thud:
            return Spec(duration: 0.22, startFreq: 150, endFreq: 62,
                        tone: 0.85, toneDecay: 3.2, harmonic: 0.15,
                        noise: 0.18, noiseDecay: 6, lowpass: 0.16,
                        attack: 0.002, release: 3.6)

        case .stone:
            return Spec(duration: 0.2, startFreq: 320, endFreq: 190,
                        tone: 0.5, toneDecay: 4, harmonic: 0.55,
                        noise: 0.55, noiseDecay: 7, lowpass: 0.3,
                        transient: 0.5, attack: 0.001, release: 4.5)

        case .leaves:
            return Spec(duration: 0.34, startFreq: 300, endFreq: 260,
                        tone: 0.05, toneDecay: 2,
                        noise: 0.7, noiseDecay: 2.6, highpass: 0.72,
                        attack: 0.02, release: 2.4)

        case .rustle:
            return Spec(duration: 0.2, startFreq: 400, endFreq: 380,
                        tone: 0.04, toneDecay: 2,
                        noise: 0.6, noiseDecay: 4, highpass: 0.8,
                        attack: 0.012, release: 3.2)

        case .chirp:
            return Spec(duration: 0.16, startFreq: 1500, endFreq: 2600,
                        tone: 0.65, toneDecay: 3.5, noise: 0.05, noiseDecay: 6,
                        attack: 0.006, release: 4)

        case .crunch:
            return Spec(duration: 0.26, startFreq: 700, endFreq: 420,
                        tone: 0.12, toneDecay: 3,
                        noise: 0.8, noiseDecay: 5.5, highpass: 0.45,
                        transient: 0.6, attack: 0.002, release: 4.2)

        case .tap:
            return Spec(duration: 0.07, startFreq: 1200, endFreq: 900,
                        tone: 0.45, toneDecay: 10, noise: 0.35, noiseDecay: 12,
                        highpass: 0.5, transient: 0.4, attack: 0.0008, release: 8)

        case .knock:
            return Spec(duration: 0.18, startFreq: 420, endFreq: 240,
                        tone: 0.7, toneDecay: 5, harmonic: 0.3,
                        noise: 0.2, noiseDecay: 8, lowpass: 0.35,
                        transient: 0.35, attack: 0.001, release: 5)

        case .wood:
            return Spec(duration: 0.24, startFreq: 260, endFreq: 160,
                        tone: 0.72, toneDecay: 3.6, harmonic: 0.42,
                        noise: 0.22, noiseDecay: 6, lowpass: 0.28,
                        attack: 0.0015, release: 4)

        case .metal:
            return Spec(duration: 0.5, startFreq: 1900, endFreq: 1750,
                        tone: 0.42, toneDecay: 1.5, harmonic: 0.85,
                        noise: 0.15, noiseDecay: 4, highpass: 0.6,
                        transient: 0.3, attack: 0.0008, release: 1.9)

        case .swish:
            return Spec(duration: 0.3, startFreq: 600, endFreq: 1400,
                        tone: 0.05, toneDecay: 2,
                        noise: 0.55, noiseDecay: 2.2, highpass: 0.5,
                        attack: 0.05, release: 2.6)
        }
    }
}
