import Foundation

/// Applies "Whisper Optimal" acoustic shaping to mono PCM audio.
///
/// Designed based on speech acoustic research for OpenAI Whisper:
/// 1. 80 Hz 2nd-order High-Pass Butterworth filter (strips HVAC rumble, desk thumps, mic handling pops).
/// 2. 280 Hz Parametric notch filter (-2.5 dB, Q=1.2) to attenuate chest resonance and proximity effect.
/// 3. Loudness normalization to target ~-16 LUFS (-15 dBFS RMS) with finite peak limiter (0.95 max).
nonisolated final class WhisperOptimalAudioProcessor: Sendable {
    private struct BiquadCoefficients: Sendable {
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float

        static func highPass(cutoff: Double, sampleRate: Double, q: Double = 0.70710678) -> BiquadCoefficients {
            let omega = 2.0 * Double.pi * cutoff / sampleRate
            let cosOmega = cos(omega)
            let alpha = sin(omega) / (2.0 * q)

            let b0 = (1.0 + cosOmega) / 2.0
            let b1 = -(1.0 + cosOmega)
            let b2 = (1.0 + cosOmega) / 2.0
            let a0 = 1.0 + alpha
            let a1 = -2.0 * cosOmega
            let a2 = 1.0 - alpha

            return BiquadCoefficients(
                b0: Float(b0 / a0),
                b1: Float(b1 / a0),
                b2: Float(b2 / a0),
                a1: Float(a1 / a0),
                a2: Float(a2 / a0)
            )
        }

        static func peaking(centerFreq: Double, gainDB: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
            let a = pow(10.0, gainDB / 40.0)
            let omega = 2.0 * Double.pi * centerFreq / sampleRate
            let cosOmega = cos(omega)
            let alpha = sin(omega) / (2.0 * q)

            let b0 = 1.0 + (alpha * a)
            let b1 = -2.0 * cosOmega
            let b2 = 1.0 - (alpha * a)
            let a0 = 1.0 + (alpha / a)
            let a1 = -2.0 * cosOmega
            let a2 = 1.0 - (alpha / a)

            return BiquadCoefficients(
                b0: Float(b0 / a0),
                b1: Float(b1 / a0),
                b2: Float(b2 / a0),
                a1: Float(a1 / a0),
                a2: Float(a2 / a0)
            )
        }
    }

    private let targetRMS: Float
    private let maxHeadroom: Float

    init(targetRMS: Float = 0.18, maxHeadroom: Float = 0.95) {
        self.targetRMS = targetRMS
        self.maxHeadroom = maxHeadroom
    }

    func applyAcousticFilters(samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }

        let hpf = BiquadCoefficients.highPass(cutoff: 80.0, sampleRate: sampleRate)
        let deMuffler = BiquadCoefficients.peaking(
            centerFreq: 280.0,
            gainDB: -2.5,
            q: 1.2,
            sampleRate: sampleRate
        )

        var filtered = applyBiquad(coefficients: hpf, samples: samples)
        filtered = applyBiquad(coefficients: deMuffler, samples: filtered)
        return filtered
    }

    func process(samples: [Float], sampleRate: Double) -> [Float] {
        let filtered = applyAcousticFilters(samples: samples, sampleRate: sampleRate)
        return normalizeLevel(samples: filtered)
    }

    private func applyBiquad(coefficients: BiquadCoefficients, samples: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0

        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 =
                (coefficients.b0 * x0)
                + (coefficients.b1 * x1)
                + (coefficients.b2 * x2)
                - (coefficients.a1 * y1)
                - (coefficients.a2 * y2)

            output[i] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }

        return output
    }

    private func normalizeLevel(samples: [Float]) -> [Float] {
        var sumSquares: Double = 0
        for s in samples {
            let d = Double(s)
            sumSquares += d * d
        }
        let rms = Float(sqrt(sumSquares / Double(samples.count)))

        // If pure silence or near-zero, avoid amplification
        guard rms > 0.0001 else {
            return samples.map { max(-maxHeadroom, min(maxHeadroom, $0)) }
        }

        // Target gain bounded between -12 dB (0.25x) and +14 dB (5.0x)
        let rawGain = targetRMS / rms
        let gain = max(0.25, min(5.0, rawGain))

        var output = samples.map { $0 * gain }

        // Headroom conditioning to prevent clipping
        var peak: Float = 0
        for s in output {
            let a = abs(s)
            if a > peak { peak = a }
        }

        if peak > maxHeadroom {
            let attenuation = maxHeadroom / peak
            output = output.map { $0 * attenuation }
        }

        return output
    }
}
