import Accelerate
import Foundation

nonisolated enum VoiceBandAnalyzer {
    static let defaultVoiceBand: ClosedRange<Double> = 80...4_000
    private static let minimumRMS: Float = 0.002
    private static let responseGain = 1.55

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
        guard sampleRate > 0 else { return 0 }
        let fftSize = largestPowerOfTwo(notExceeding: samples.count)
        guard fftSize >= 64 else { return 0 }

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
        guard totalPower > 0 else { return 0 }

        let binWidth = sampleRate / Double(fftSize)
        let lowerBin = max(1, Int(ceil(voiceBand.lowerBound / binWidth)))
        let upperBin = min(halfSize - 1, Int(floor(voiceBand.upperBound / binWidth)))
        guard lowerBin <= upperBin else { return 0 }

        let bandPower = magnitudesSquared[lowerBin...upperBin].reduce(Float(0), +)
        return min(1, max(0, Double(bandPower / totalPower)))
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare)
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
