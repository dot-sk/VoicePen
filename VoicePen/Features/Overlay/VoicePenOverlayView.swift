import SwiftUI

struct VoicePenOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ZStack {
                switch viewModel.state {
                case let .recording(startedAt, level):
                    ListeningOverlayContent(
                        elapsedText: elapsedTimeText(since: startedAt),
                        level: level
                    )
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
            .frame(width: 360, height: 128)
        }
    }
}

private struct ListeningOverlayContent: View {
    let elapsedText: String
    let level: Double?

    var body: some View {
        VStack(spacing: 7) {
            ListeningMicrophoneIndicatorView(level: level)

            Text(elapsedText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundStyle(Color(white: 0.58, opacity: 0.92))
                .offset(y: -8)
        }
    }
}

private struct TextStatusOverlayContent: View {
    let title: String
    let subtitle: String
    let progress: Double?
    let symbolName: String
    let cancelAction: (() -> Void)?

    private var showsSubtitle: Bool {
        title == "VoicePen needs attention"
    }

    private var chipMaxWidth: CGFloat {
        showsSubtitle ? 320 : (cancelAction == nil ? 210 : 252)
    }

    var body: some View {
        HStack(spacing: 9) {
            statusSymbol
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if showsSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let cancelAction {
                Button {
                    cancelAction()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 23, height: 23)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .help("Cancel transcription")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, showsSubtitle ? 9 : 8)
        .frame(maxWidth: chipMaxWidth)
        .background {
            Capsule()
                .fill(.black.opacity(0.16))
                .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private var statusSymbol: some View {
        if title == "VoicePen needs attention" {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.yellow)
        } else if progress != nil {
            ProgressView(value: progress, total: 1.0)
                .controlSize(.small)
        } else if title == "Inserted" || symbolName == "checkmark" {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .bold))
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
