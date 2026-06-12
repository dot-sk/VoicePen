@preconcurrency import AVFoundation
import Foundation

nonisolated final class LiveRecordingMeter: @unchecked Sendable {
    typealias Analyzer = @Sendable ([Float], Double) -> Double

    private let analysisWindowSampleCount: Int
    private let attackSmoothingWeight: Double
    private let releaseSmoothingWeight: Double
    private let silenceReleaseSmoothingWeight: Double
    private let silenceLevelThreshold: Double
    private let analyzer: Analyzer
    private let lock = NSLock()
    private let analysisQueue = DispatchQueue(label: "voicepen.live-recording-meter.analysis", qos: .userInteractive)
    private var samples: [Float] = []
    private var writeIndex = 0
    private var availableSampleCount = 0
    private var sampleRate: Double = 0
    private var latestLevel: Double?
    private var isAnalysisScheduled = false
    private var generation: UInt64 = 0
    private var sampleVersion: UInt64 = 0
    private var analyzedSampleVersion: UInt64 = 0

    init(
        analysisWindowSampleCount: Int = VoicePenConfig.recordingMeterAnalysisWindowSampleCount,
        smoothingWeight: Double = 0.74,
        releaseSmoothingWeight: Double = 0.18,
        silenceReleaseSmoothingWeight: Double = 0.58,
        silenceLevelThreshold: Double = 0.025,
        analyzer: @escaping Analyzer = {
            VoiceBandAnalyzer.collapsedSpectrumLevel(samples: $0, sampleRate: $1)
        }
    ) {
        self.analysisWindowSampleCount = max(1, analysisWindowSampleCount)
        attackSmoothingWeight = min(1, max(0, smoothingWeight))
        self.releaseSmoothingWeight = min(1, max(0, releaseSmoothingWeight))
        self.silenceReleaseSmoothingWeight = min(1, max(0, silenceReleaseSmoothingWeight))
        self.silenceLevelThreshold = min(1, max(0, silenceLevelThreshold))
        self.analyzer = analyzer
        samples = [Float](repeating: 0, count: self.analysisWindowSampleCount)
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            return
        }

        ingest(
            samplesPointer: channelData[0],
            count: Int(buffer.frameLength),
            sampleRate: buffer.format.sampleRate
        )
    }

    func ingest(samples newSamples: [Float], sampleRate: Double) {
        newSamples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            ingest(samplesPointer: baseAddress, count: pointer.count, sampleRate: sampleRate)
        }
    }

    func currentLevel() -> Double? {
        lock.lock()
        let latestLevel = latestLevel
        lock.unlock()
        return latestLevel
    }

    func reset() {
        lock.lock()
        latestLevel = nil
        generation &+= 1
        isAnalysisScheduled = false
        writeIndex = 0
        availableSampleCount = 0
        sampleRate = 0
        sampleVersion = 0
        analyzedSampleVersion = 0
        lock.unlock()
    }

    func flushPendingAnalysis() async {
        await withCheckedContinuation { continuation in
            analysisQueue.async {
                continuation.resume()
            }
        }
    }

    private func analyzePendingSamples() {
        while true {
            guard let analysis = nextAnalysis() else { return }

            let rawLevel = min(1, max(0, analyzer(analysis.samples, analysis.sampleRate)))
            let smoothedLevel = envelopedLevel(
                rawLevel: rawLevel,
                previousLevel: analysis.previousLevel
            )

            lock.lock()
            if generation == analysis.generation {
                latestLevel = smoothedLevel
            }
            lock.unlock()
        }
    }

    private func envelopedLevel(rawLevel: Double, previousLevel: Double?) -> Double {
        guard let previousLevel else { return rawLevel }

        let weight: Double
        if rawLevel >= previousLevel {
            weight = attackSmoothingWeight
        } else if rawLevel <= silenceLevelThreshold {
            weight = silenceReleaseSmoothingWeight
        } else {
            weight = releaseSmoothingWeight
        }

        return previousLevel * (1 - weight) + rawLevel * weight
    }

    private func nextAnalysis() -> PendingAnalysis? {
        let snapshot: [Float]
        let snapshotSampleRate: Double
        let previousLevel: Double?

        lock.lock()
        guard availableSampleCount > 0, sampleRate > 0 else {
            isAnalysisScheduled = false
            lock.unlock()
            return nil
        }
        guard sampleVersion != analyzedSampleVersion else {
            isAnalysisScheduled = false
            lock.unlock()
            return nil
        }

        analyzedSampleVersion = sampleVersion
        snapshot = analysisSnapshotLocked()
        snapshotSampleRate = sampleRate
        previousLevel = latestLevel
        let generation = generation
        lock.unlock()

        return PendingAnalysis(
            samples: snapshot,
            sampleRate: snapshotSampleRate,
            previousLevel: previousLevel,
            generation: generation
        )
    }

    private func ingest(
        samplesPointer: UnsafePointer<Float>,
        count: Int,
        sampleRate: Double
    ) {
        guard count > 0, sampleRate > 0 else { return }

        lock.lock()
        appendSamplesLocked(samplesPointer: samplesPointer, count: count)
        self.sampleRate = sampleRate
        sampleVersion &+= 1
        scheduleAnalysisLocked()
        lock.unlock()
    }

    private func scheduleAnalysisLocked() {
        guard !isAnalysisScheduled else { return }

        isAnalysisScheduled = true
        analysisQueue.async { [weak self] in
            self?.analyzePendingSamples()
        }
    }

    private func appendSamplesLocked(samplesPointer: UnsafePointer<Float>, count: Int) {
        let countToCopy = min(count, analysisWindowSampleCount)
        let source = samplesPointer.advanced(by: count - countToCopy)
        let firstCopyCount = min(countToCopy, analysisWindowSampleCount - writeIndex)

        samples.withUnsafeMutableBufferPointer { destination in
            guard let baseAddress = destination.baseAddress else { return }
            baseAddress.advanced(by: writeIndex).update(from: source, count: firstCopyCount)

            let remainingCount = countToCopy - firstCopyCount
            if remainingCount > 0 {
                baseAddress.update(from: source.advanced(by: firstCopyCount), count: remainingCount)
            }
        }

        writeIndex = (writeIndex + countToCopy) % analysisWindowSampleCount
        availableSampleCount = min(analysisWindowSampleCount, availableSampleCount + countToCopy)
    }

    private func analysisSnapshotLocked() -> [Float] {
        guard availableSampleCount > 0 else { return [] }

        let startIndex =
            (writeIndex - availableSampleCount + analysisWindowSampleCount)
            % analysisWindowSampleCount
        if startIndex + availableSampleCount <= analysisWindowSampleCount {
            return Array(samples[startIndex..<(startIndex + availableSampleCount)])
        }

        let firstRange = samples[startIndex..<analysisWindowSampleCount]
        let secondCount = availableSampleCount - firstRange.count
        return Array(firstRange) + Array(samples[0..<secondCount])
    }
}

nonisolated private struct PendingAnalysis: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let previousLevel: Double?
    let generation: UInt64
}
