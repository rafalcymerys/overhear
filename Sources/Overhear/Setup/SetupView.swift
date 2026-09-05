import SwiftUI

/// The one window a new install sees: a card per requirement, the topmost
/// unfinished one open, the rest folded to a line saying what they settled.
struct SetupView: View {
    @ObservedObject var setup: SetupCoordinator
    /// Observed alongside the coordinator because the cards read them
    /// directly — a view watching only `SetupCoordinator` would miss a
    /// permission granted in System Settings and either download's progress.
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var models: TranscriptionModelService
    @ObservedObject var wakeWords: WakeWordSetup
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Let's get you set up")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("To use Overhear, you need to download a transcription model and grant some basic permissions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 8) {
                ForEach(SetupRequirement.allCases) { requirement in
                    SetupCard(setup: setup,
                              models: models,
                              wakeWords: wakeWords,
                              requirement: requirement)
                }
            }

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .topLeading)
    }
}

/// One requirement: a heading that is always there, and a body that is there
/// while there is something to say or do.
private struct SetupCard: View {
    @ObservedObject var setup: SetupCoordinator
    @ObservedObject var models: TranscriptionModelService
    @ObservedObject var wakeWords: WakeWordSetup
    let requirement: SetupRequirement

    private var isSatisfied: Bool { setup.isSatisfied(requirement) }
    private var isExpanded: Bool { setup.isExpanded(requirement) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded {
                body(for: requirement)
                    .padding(.leading, 24)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var header: some View {
        Button {
            withAnimation { setup.toggle(requirement) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSatisfied ? "checkmark.circle.fill" : requirement.symbol)
                    .foregroundStyle(isSatisfied ? Color.green : Color.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(.body, weight: .medium))
                Spacer(minLength: 8)
                if let summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !isExpanded && !isSatisfied {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Inert rather than disabled: a settled card does not open, but it
        // should not go grey either — the tick and what it settled are the
        // point of the line.
        .allowsHitTesting(!isSatisfied)
        .accessibilityLabel(title)
        .accessibilityValue(summary ?? (isExpanded ? "expanded" : "collapsed"))
    }

    private var title: String {
        guard case .model = requirement else { return requirement.title }
        return setup.modelCardTitle
    }

    /// The right of the heading: what the card settled, or how far its download
    /// has got. Nothing while it is waiting on the user, whose card is open and
    /// says more than a word could.
    private var summary: String? {
        if isSatisfied {
            if case .permission = requirement { return "Granted" }
            return "Downloaded"
        }
        switch requirement {
        case .model:
            guard let fraction = setup.downloadProgress else { return nil }
            return "\(Int(fraction * 100))%"
        case .wakeWords:
            guard let fraction = setup.wakeWordProgress else { return nil }
            return "\(Int(fraction * 100))%"
        case .permission:
            return nil
        }
    }

    /// Only the card the window is actually waiting on is picked out. A
    /// download that is running is open too, and outlining both would leave
    /// nothing saying which one wants the user.
    private var borderColor: Color {
        if case .model = requirement, setup.failure != nil {
            return .red.opacity(0.5)
        }
        if case .wakeWords = requirement, setup.wakeWordFailure != nil {
            return .red.opacity(0.5)
        }
        return setup.firstNeedingAttention == requirement
            ? .accentColor.opacity(0.6)
            : Color.secondary.opacity(0.25)
    }

    @ViewBuilder
    private func body(for requirement: SetupRequirement) -> some View {
        switch requirement {
        case .model:
            modelBody
        case .wakeWords:
            wakeWordBody
        case let .permission(permission):
            VStack(alignment: .leading, spacing: 8) {
                explanation(requirement.explanation)
                if !isSatisfied {
                    Button(setup.buttonTitle(for: permission)) {
                        setup.request(permission)
                    }
                    .modifier(DefaultAction(enabled: setup.firstNeedingAttention == requirement))
                }
            }
        }
    }

    @ViewBuilder
    private var modelBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = setup.failure {
                explanation("The download failed — \(failure)")
                HStack {
                    Button("Choose Another Model") { setup.chooseAnotherModel() }
                    Button("Try Again") { setup.download() }
                        .keyboardShortcut(.defaultAction)
                }
            } else if let fraction = setup.downloadProgress {
                let received = Int64(Double(setup.chosenModel.downloadSize) * fraction)
                ProgressView(value: fraction)
                Text("Downloading · \(byteCount(received)) of \(byteCount(setup.chosenModel.downloadSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { setup.cancelDownload() }
            } else if !isSatisfied {
                explanation(requirement.explanation)
                modelPicker
                Button("Download") { setup.download() }
                    .modifier(DefaultAction(enabled: setup.firstNeedingAttention == requirement))
            }
        }
    }

    /// The card that asks for nothing. Its explanation stays up while the
    /// download runs, because there is no earlier moment to read it in — the
    /// card is already downloading the first time it is seen.
    @ViewBuilder
    private var wakeWordBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            explanation(requirement.explanation)
            if let failure = setup.wakeWordFailure {
                explanation(failure)
                Button("Try Again") { setup.retryWakeWords() }
            } else if let fraction = setup.wakeWordProgress {
                ProgressView(value: fraction)
                Text(setup.wakeWordStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The catalogue as the Transcription pane groups it, so the two places a
    /// model is chosen offer the same thing under the same headings.
    private var modelPicker: some View {
        Picker("Model", selection: $setup.chosenModelID) {
            ForEach(ModelCatalog.grouped(), id: \.engine) { group in
                Section(group.engine.displayName) {
                    ForEach(group.models) { model in
                        Text(label(for: model)).tag(model.id)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(!setup.canChooseModel)
    }

    private func label(for model: TranscriptionModel) -> String {
        var parts = [model.displayName, byteCount(model.downloadSize)]
        if !model.supportsEveryLanguage || model.engine != .whisper {
            parts.append(model.languageSummary)
        }
        if let note = model.note {
            parts.append(note)
        }
        return parts.joined(separator: " · ")
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.overhear.string(fromByteCount: bytes)
    }
}

/// `keyboardShortcut` has no conditional form, so wrap it. Only the card the
/// window is waiting on gets the return key.
private struct DefaultAction: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}
