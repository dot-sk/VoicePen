import SwiftUI

struct VoicePenOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ZStack {
                switch viewModel.state {
                case let .recording(startedAt, _):
                    ListeningOverlayContent(elapsedText: elapsedTimeText(since: startedAt))
                case let .transcribing(stage, progress):
                    TextStatusOverlayContent(
                        title: stage.rawValue,
                        subtitle: "Working locally",
                        progress: progress,
                        symbolName: "text.cursor",
                        cancelAction: viewModel.onCancelTranscription
                    )
                case let .done(message):
                    TextStatusOverlayContent(
                        title: message,
                        subtitle: "Ready",
                        progress: nil,
                        symbolName: "checkmark",
                        cancelAction: nil
                    )
                case let .error(message):
                    TextStatusOverlayContent(
                        title: "VoicePen needs attention",
                        subtitle: message,
                        progress: nil,
                        symbolName: "exclamationmark.triangle",
                        cancelAction: nil
                    )
                case .hidden:
                    EmptyView()
                }
            }
            .frame(width: 360, height: 104)
        }
    }
}

private struct ListeningOverlayContent: View {
    let elapsedText: String

    var body: some View {
        VStack(spacing: 7) {
            ListeningMicrophoneIndicatorView()

            Text(elapsedText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct TextStatusOverlayContent: View {
    let title: String
    let subtitle: String
    let progress: Double?
    let symbolName: String
    let cancelAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            statusSymbol
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let cancelAction {
                Button {
                    cancelAction()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Cancel transcription")
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 340, height: 68)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusSymbol: some View {
        if title == "VoicePen needs attention" {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.yellow)
        } else if progress != nil {
            ProgressView(value: progress, total: 1.0)
                .controlSize(.small)
        } else if title == "Inserted" || symbolName == "checkmark" {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.green)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

private extension VoicePenOverlayView {
    private func elapsedTimeText(since startDate: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(startDate))
        return String(format: "%.1fs", elapsed)
    }
}
