import Accelerate
import Foundation

nonisolated struct VoiceMeterFeatures: Equatable, Sendable {
    let level: Double
    let loudness: Double
    let voicePresence: Double
    let body: Double
    let vowelCore: Double
    let clarity: Double
    let airDetail: Double
    let strongestBand: Double
    let weightedBandStack: Double
    let collapsedSpectrum: Double

    static let silent = VoiceMeterFeatures(
        level: 0,
        loudness: 0,
        voicePresence: 0,
        body: 0,
        vowelCore: 0,
        clarity: 0,
        airDetail: 0,
        strongestBand: 0,
        weightedBandStack: 0,
        collapsedSpectrum: 0
    )
}

nonisolated enum VoiceBandAnalyzer {
    static let defaultVoiceBand: ClosedRange<Double> = 80...4_000
    private static let minimumRMS: Float = 0.002
    private static let responseGain = 1.55
    private static let collapsedSpectrumResponseGain = 1.45
    private static let loudnessFloorDecibels = -48.0
    private static let bodyBand: ClosedRange<Double> = 80...220
    private static let vowelCoreBand: ClosedRange<Double> = 220...700
    private static let clarityBand: ClosedRange<Double> = 700...1_600
    private static let airDetailBand: ClosedRange<Double> = 1_600...4_000

    static func collapsedSpectrumLevel(samples: [Float], sampleRate: Double) -> Double {
        voiceMeterFeatures(samples: samples, sampleRate: sampleRate).level
    }

    static func voiceMeterFeatures(samples: [Float], sampleRate: Double) -> VoiceMeterFeatures {
        guard !samples.isEmpty, sampleRate > 0 else { return .silent }

        let rms = rootMeanSquare(samples)
        let loudness = normalizedLoudness(forRMS: rms)
        guard loudness > 0 else { return .silent }
        guard let spectrum = spectrumEnergy(samples: samples, sampleRate: sampleRate),
            spectrum.totalPower > 0
        else {
            return .silent
        }

        let bodyPower = spectrum.power(in: bodyBand)
        let vowelCorePower = spectrum.power(in: vowelCoreBand)
        let clarityPower = spectrum.power(in: clarityBand)
        let airDetailPower = spectrum.power(in: airDetailBand)
        let voicePower = bodyPower + vowelCorePower + clarityPower + airDetailPower
        guard voicePower > 0 else {
            return VoiceMeterFeatures(
                level: 0,
                loudness: loudness,
                voicePresence: 0,
                body: 0,
                vowelCore: 0,
                clarity: 0,
                airDetail: 0,
                strongestBand: 0,
                weightedBandStack: 0,
                collapsedSpectrum: 0
            )
        }

        let voicePowerDouble = Double(voicePower)
        let body = Double(bodyPower) / voicePowerDouble
        let vowelCore = Double(vowelCorePower) / voicePowerDouble
        let clarity = Double(clarityPower) / voicePowerDouble
        let airDetail = Double(airDetailPower) / voicePowerDouble
        let strongestBand = max(body, vowelCore, clarity, airDetail)
        let weightedBandStack =
            body * 0.95
            + vowelCore
            + clarity * 0.85
            + airDetail * 0.45
        let collapsedSpectrum = min(
            1,
            max(0, 0.55 * strongestBand + 0.45 * weightedBandStack)
        )
        let voicePresenceRatio = min(1, max(0, Double(voicePower / spectrum.totalPower)))
        let voicePresence = pow(voicePresenceRatio, 0.55)
        let voiceCharacterPresence = min(1, body + vowelCore + clarity + airDetail * 0.35)
        let level = min(
            1,
            max(
                0,
                loudness
                    * voicePresence
                    * voiceCharacterPresence
                    * collapsedSpectrum
                    * collapsedSpectrumResponseGain
            )
        )

        return VoiceMeterFeatures(
            level: level,
            loudness: loudness,
            voicePresence: voicePresence,
            body: body,
            vowelCore: vowelCore,
            clarity: clarity,
            airDetail: airDetail,
            strongestBand: strongestBand,
            weightedBandStack: weightedBandStack,
            collapsedSpectrum: collapsedSpectrum
        )
    }

    static func normalizedVoiceBandLevel(
        samples: [Float],
        sampleRate: Double,
        voiceBand: ClosedRange<Double> = defaultVoiceBand
    ) -> Double {
        guard !samples.isEmpty, sampleRate > 0 else { return 0 }

        let rms = rootMeanSquare(samples)
        guard rms >= minimumRMS else { return 0 }

        let ratio = voiceBandRatio(
            samples: samples,
            sampleRate: sampleRate,
            voiceBand: voiceBand
        )
        let decibels = 20 * log10(Double(max(rms, .leastNonzeroMagnitude)))
        let amplitude = (min(0, max(-44, decibels)) + 44) / 44
        let speechPresence = pow(ratio, 0.35)

        return min(1, max(0, amplitude * speechPresence * responseGain))
    }

    static func voiceBandRatio(
        samples: [Float],
        sampleRate: Double,
        voiceBand: ClosedRange<Double> = defaultVoiceBand
    ) -> Double {
        guard let spectrum = spectrumEnergy(samples: samples, sampleRate: sampleRate),
            spectrum.totalPower > 0
        else {
            return 0
        }

        let bandPower = spectrum.power(in: voiceBand)
        return min(1, max(0, Double(bandPower / spectrum.totalPower)))
    }

    private static func normalizedLoudness(forRMS rms: Float) -> Double {
        guard rms >= minimumRMS else { return 0 }

        let decibels = 20 * log10(Double(max(rms, .leastNonzeroMagnitude)))
        let normalized =
            (min(0, max(loudnessFloorDecibels, decibels)) - loudnessFloorDecibels)
            / abs(loudnessFloorDecibels)
        return min(1, max(0, pow(normalized, 0.75)))
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare)
    }

    private static func spectrumEnergy(samples: [Float], sampleRate: Double) -> SpectrumEnergy? {
        guard sampleRate > 0 else { return nil }
        let fftSize = largestPowerOfTwo(notExceeding: samples.count)
        guard fftSize >= 64 else { return nil }

        var windowedSamples = Array(samples.suffix(fftSize))
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        let halfSize = fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imaginary = [Float](repeating: 0, count: halfSize)
        var magnitudesSquared = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var splitComplex = DSPSplitComplex(
                    realp: realPointer.baseAddress!,
                    imagp: imaginaryPointer.baseAddress!
                )

                windowedSamples.withUnsafeBufferPointer { samplePointer in
                    samplePointer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: halfSize
                    ) { complexPointer in
                        vDSP_ctoz(
                            complexPointer,
                            2,
                            &splitComplex,
                            1,
                            vDSP_Length(halfSize)
                        )
                    }
                }

                let log2Size = vDSP_Length(log2(Double(fftSize)))
                guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
                    return
                }
                defer { vDSP_destroy_fftsetup(setup) }

                vDSP_fft_zrip(setup, &splitComplex, 1, log2Size, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(
                    &splitComplex,
                    1,
                    &magnitudesSquared,
                    1,
                    vDSP_Length(halfSize)
                )
            }
        }

        let totalPower = magnitudesSquared.reduce(Float(0), +)
        return SpectrumEnergy(
            magnitudesSquared: magnitudesSquared,
            totalPower: totalPower,
            binWidth: sampleRate / Double(fftSize)
        )
    }

    private static func largestPowerOfTwo(notExceeding value: Int) -> Int {
        guard value > 0 else { return 0 }
        var result = 1
        while result * 2 <= value {
            result *= 2
        }
        return result
    }
}

nonisolated private struct SpectrumEnergy {
    let magnitudesSquared: [Float]
    let totalPower: Float
    let binWidth: Double

    func power(in band: ClosedRange<Double>) -> Float {
        let halfSize = magnitudesSquared.count
        let lowerBin = max(1, Int(ceil(band.lowerBound / binWidth)))
        let upperBin = min(halfSize - 1, Int(floor(band.upperBound / binWidth)))
        guard lowerBin <= upperBin else { return 0 }

        return magnitudesSquared[lowerBin...upperBin].reduce(Float(0), +)
    }
}
