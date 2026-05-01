import SwiftUI

struct ListeningMicrophoneIndicatorView: View {
    @State private var isListening = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .strokeBorder(.white.opacity(isListening ? 0 : 0.42), lineWidth: 1.6)
                    .frame(
                        width: isListening ? CGFloat(70 + index * 18) : 28,
                        height: isListening ? CGFloat(82 + index * 18) : 52
                    )
                    .scaleEffect(isListening ? 1.0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.45)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.28),
                        value: isListening
                    )
            }

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemRed).opacity(0.95),
                            Color(nsColor: .systemPink).opacity(0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 54)
                .shadow(color: Color(nsColor: .systemRed).opacity(0.34), radius: 14, y: 4)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.34), lineWidth: 1)
                        .padding(1)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.82))
                        .frame(width: 3, height: 17)
                        .padding(.top, 10)
                }

            Capsule()
                .fill(.white.opacity(0.78))
                .frame(width: 12, height: 3)
                .offset(y: 15)

            Capsule()
                .fill(.white.opacity(0.7))
                .frame(width: 3, height: 10)
                .offset(y: 23)
        }
        .frame(width: 112, height: 88)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        }
        .onAppear {
            isListening = true
        }
        .onDisappear {
            isListening = false
        }
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
