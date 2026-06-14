import Foundation

struct MeetingSourceEnergyIndex {
    private let profilesBySource: [MeetingSourceKind: [MeetingSourceEnergyProfile]]

    init(
        sourceSpans: [MeetingAudioSourceSpan],
        binDuration: TimeInterval = 0.1,
        audioFileIO: MeetingAudioFileIO
    ) {
        var profilesBySource: [MeetingSourceKind: [MeetingSourceEnergyProfile]] = [:]
        for span in sourceSpans {
            guard
                let profile = MeetingSourceEnergyProfile(
                    span: span,
                    binDuration: binDuration,
                    audioFileIO: audioFileIO
                )
            else {
                continue
            }
            profilesBySource[span.source, default: []].append(profile)
        }
        self.profilesBySource = profilesBySource
    }

    func dominantEnergy(
        for source: MeetingSourceKind,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval
    ) -> Double {
        profilesBySource[source]?
            .compactMap { $0.averageEnergy(segmentStart: segmentStart, segmentEnd: segmentEnd) }
            .max() ?? 0
    }

    func activeBounds(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        threshold: Double = 0.0001
    ) -> (start: TimeInterval, end: TimeInterval)? {
        profilesBySource.values
            .flatMap { $0 }
            .compactMap { $0.activeBounds(segmentStart: segmentStart, segmentEnd: segmentEnd, threshold: threshold) }
            .reduce(nil) { partial, bounds in
                guard let partial else { return bounds }
                return (
                    start: min(partial.start, bounds.start),
                    end: max(partial.end, bounds.end)
                )
            }
    }
}

struct MeetingSourceEnergyProfile {
    var startOffset: TimeInterval
    var duration: TimeInterval
    var binDuration: TimeInterval
    var bins: [Double]

    init?(
        span: MeetingAudioSourceSpan,
        binDuration: TimeInterval,
        audioFileIO: MeetingAudioFileIO
    ) {
        guard span.duration > 0, binDuration > 0 else { return nil }
        guard let frameLevelWindow = try? audioFileIO.averageAbsoluteFrameLevels(for: span) else { return nil }

        let binCount = max(1, Int((span.duration / binDuration).rounded(.up)))
        var totals = Array(repeating: 0.0, count: binCount)
        var counts = Array(repeating: 0, count: binCount)
        let framesPerBin = max(1, Int((binDuration * frameLevelWindow.sampleRate).rounded(.up)))

        for frame in frameLevelWindow.levels.indices {
            let binIndex = min(binCount - 1, frame / framesPerBin)
            totals[binIndex] += frameLevelWindow.levels[frame]
            counts[binIndex] += 1
        }

        self.startOffset = span.startOffset
        self.duration = span.duration
        self.binDuration = binDuration
        self.bins = totals.enumerated().map { index, total in
            let count = counts[index]
            return count > 0 ? total / Double(count) : 0
        }
    }

    func averageEnergy(segmentStart: TimeInterval, segmentEnd: TimeInterval) -> Double? {
        let profileEnd = startOffset + duration
        let overlapStart = max(segmentStart, startOffset)
        let overlapEnd = min(segmentEnd, profileEnd)
        guard overlapEnd > overlapStart, !bins.isEmpty else { return nil }

        var weightedTotal = 0.0
        var totalDuration = 0.0
        for (index, energy) in bins.enumerated() {
            let binStart = startOffset + (Double(index) * binDuration)
            let binEnd = min(profileEnd, binStart + binDuration)
            let binOverlapStart = max(overlapStart, binStart)
            let binOverlapEnd = min(overlapEnd, binEnd)
            guard binOverlapEnd > binOverlapStart else { continue }
            let binOverlapDuration = binOverlapEnd - binOverlapStart
            weightedTotal += energy * binOverlapDuration
            totalDuration += binOverlapDuration
        }

        guard totalDuration > 0 else { return nil }
        return weightedTotal / totalDuration
    }

    func activeBounds(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        threshold: Double
    ) -> (start: TimeInterval, end: TimeInterval)? {
        let profileEnd = startOffset + duration
        let overlapStart = max(segmentStart, startOffset)
        let overlapEnd = min(segmentEnd, profileEnd)
        guard overlapEnd > overlapStart, !bins.isEmpty else { return nil }

        var firstActiveStart: TimeInterval?
        var lastActiveEnd: TimeInterval?
        for (index, energy) in bins.enumerated() where energy > threshold {
            let binStart = startOffset + (Double(index) * binDuration)
            let binEnd = min(profileEnd, binStart + binDuration)
            let binOverlapStart = max(overlapStart, binStart)
            let binOverlapEnd = min(overlapEnd, binEnd)
            guard binOverlapEnd > binOverlapStart else { continue }
            firstActiveStart = firstActiveStart.map { min($0, binOverlapStart) } ?? binOverlapStart
            lastActiveEnd = lastActiveEnd.map { max($0, binOverlapEnd) } ?? binOverlapEnd
        }

        guard let firstActiveStart, let lastActiveEnd else { return nil }
        return (firstActiveStart, lastActiveEnd)
    }
}
