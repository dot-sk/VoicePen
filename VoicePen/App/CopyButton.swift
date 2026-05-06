import SwiftUI

struct CopyButton: View {
    enum Presentation {
        case iconOnly
        case label
        case prominentLabel
    }

    var title = "Copy"
    var copiedTitle = "Copied"
    var systemImage = "doc.on.doc"
    var presentation: Presentation = .iconOnly
    var isDisabled = false
    let action: () -> Void

    @State private var isCopied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        styledButton
            .disabled(isDisabled)
            .foregroundStyle(isCopied ? .green : .primary)
            .help(isCopied ? copiedTitle : title)
            .accessibilityLabel(isCopied ? copiedTitle : title)
            .onDisappear {
                resetTask?.cancel()
            }
    }

    @ViewBuilder
    private var styledButton: some View {
        switch presentation {
        case .iconOnly:
            button
        case .label:
            button
        case .prominentLabel:
            button.buttonStyle(.borderedProminent)
        }
    }

    private var button: some View {
        Button {
            action()
            showFeedback()
        } label: {
            stableFeedbackLabel
        }
    }

    private var stableFeedbackLabel: some View {
        ZStack {
            feedbackLabel(title: title, systemImage: systemImage)
                .opacity(isCopied ? 0 : 1)
            feedbackLabel(title: copiedTitle, systemImage: "checkmark")
                .opacity(isCopied ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func feedbackLabel(title: String, systemImage: String) -> some View {
        switch presentation {
        case .iconOnly:
            Image(systemName: systemImage)
        case .label, .prominentLabel:
            Label(title, systemImage: systemImage)
        }
    }

    private func showFeedback() {
        isCopied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: VoicePenConfig.historyCopyFeedbackDuration)
            await MainActor.run {
                isCopied = false
            }
        }
    }
}
