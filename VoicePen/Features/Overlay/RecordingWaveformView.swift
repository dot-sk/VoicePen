import SwiftUI

struct ListeningMicrophoneIndicatorView: View {
    let level: Double?

    private var normalizedLevel: Double {
        min(1, max(0, level ?? 0.18))
    }

    private var stripeHeight: CGFloat {
        CGFloat(12 + normalizedLevel * 36)
    }

    private var trembleIntensity: Double {
        min(1, max(0, (normalizedLevel - 0.12) / 0.88))
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemPink).opacity(0.64),
                            Color(nsColor: .systemRed).opacity(0.96),
                            Color(nsColor: .systemPink).opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 54)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(Color(nsColor: .systemPink).opacity(0.34))
                        .frame(width: 7, height: 28)
                        .blur(radius: 3)
                        .offset(x: 6, y: 6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Capsule()
                        .fill(Color(nsColor: .systemPink).opacity(0.35))
                        .frame(width: 12, height: 22)
                        .blur(radius: 5)
                        .offset(x: -4, y: -5)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                        .padding(0.5)
                }
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let tremble = sin(time * 48) * 2.2 + sin(time * 83) * 1.1
                        let xJitter = sin(time * 71) * 0.45
                        let liveHeight = stripeHeight + CGFloat(tremble * trembleIntensity)

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(.white.opacity(0.9))
                            .frame(width: 3.2, height: liveHeight)
                            .offset(x: CGFloat(xJitter * trembleIntensity))
                            .shadow(color: .white.opacity(0.24), radius: 3, x: 0, y: 0)
                            .animation(.easeOut(duration: 0.06), value: stripeHeight)
                    }
                }
        }
        .frame(width: 112, height: 88)
        .accessibilityLabel("VoicePen is listening")
    }
}

struct RecordingWaveformView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .frame(
                        width: 4,
                        height: animate ? CGFloat(14 + index * 3) : CGFloat(8 + index)
                    )
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(index) * 0.08),
                        value: animate
                    )
            }
        }
        .frame(height: 30)
        .onAppear {
            animate = true
        }
    }
}
