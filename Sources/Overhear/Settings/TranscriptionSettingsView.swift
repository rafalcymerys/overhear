import SwiftUI

/// Which model transcribes, what it recognises, and what else could be
/// downloaded.
///
/// The active model is stated once at the top with its languages beneath it,
/// because the languages a model can transcribe are a property of that model
/// rather than a setting standing on its own — a list of models with a separate
/// language pane elsewhere leaves the user to work out that one constrains the
/// other.
struct TranscriptionSettingsView: View {
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var models: TranscriptionModelService
    @ObservedObject private var appState: AppState

    @State private var showingLanguages = false

    init(settings: AppSettings? = nil,
         models: TranscriptionModelService? = nil,
         appState: AppState? = nil) {
        self.settings = settings ?? .shared
        self.models = models ?? .shared
        self.appState = appState ?? AppState()
    }

    var body: some View {
        Form {
            Section {
                activeModel
                languages
                translation
            } header: {
                Text("Active Model")
            }

            Section {
                AvailableModels(models: models, settings: settings)
            } header: {
                Text("Available Models")
            } footer: {
                Text("\(byteCount(models.diskUsage)) used by downloaded models")
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Active model

    private var activeModel: some View {
        let model = settings.activeModel
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.semibold)
                Text("\(byteCount(models.diskUsage(of: model))) on disk · running on the Neural Engine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(loadState.color)
                    .frame(width: 7, height: 7)
                Text(loadState.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the indicator beside the active model says.
    ///
    /// It reports the model, not the dictation: a user who has stopped
    /// listening still has a loaded model, and telling them otherwise here
    /// would read as a fault.
    private enum LoadState {
        case loading, ready, failed

        var label: String {
            switch self {
            case .loading: return "Loading…"
            case .ready: return "Ready"
            case .failed: return "Not loaded"
            }
        }

        var color: Color {
            switch self {
            case .loading: return .orange
            case .ready: return .green
            case .failed: return .red
            }
        }
    }

    private var loadState: LoadState {
        if models.isDownloading(settings.activeModel) { return .loading }
        switch appState.status {
        case .loading: return .loading
        case .error: return .failed
        default: return .ready
        }
    }

    // MARK: - Languages

    private var languages: some View {
        // The explanation sits in the row with the control rather than in the
        // section's footer, which grouped forms render outside the card.
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Languages")
                Spacer()
                Button {
                    showingLanguages = true
                } label: {
                    HStack(spacing: 6) {
                        Text(languageSummary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .popover(isPresented: $showingLanguages, arrowEdge: .bottom) {
                    LanguagePicker(settings: settings)
                }
                .accessibilityLabel("Languages")
                .accessibilityValue(languageSummary)
            }
            Text(languageExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Translation sits with the languages because that is what it is about:
    /// what happens to speech in a language the user did not select.
    ///
    /// Shown for every model rather than hidden for the ones that cannot do it.
    /// A model without a translate task leaves the box unticked and disabled —
    /// which says "this model will not do that" — where hiding the row would
    /// leave someone hunting for a setting they remember having.
    private var translation: some View {
        let canTranslate = settings.activeModel.engine.canTranslate
        return VStack(alignment: .leading, spacing: 4) {
            Toggle("Translate unsupported languages", isOn: Binding(
                get: { canTranslate && settings.translateUnsupported },
                // The stored value is left alone while it cannot apply, so
                // activating a model that can translate again restores what the
                // user chose rather than a default.
                set: { if canTranslate { settings.translateUnsupported = $0 } }
            ))
            .disabled(!canTranslate)
            Text(translationExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var translationExplanation: String {
        let model = settings.activeModel
        guard model.engine.canTranslate else {
            return "\(model.displayName) cannot translate. Speech in a language you have not selected is transcribed in one you have."
        }
        return "Speech in a language you have not selected is translated to English. The languages you select are always transcribed as themselves."
    }

    /// The selection, as it reads on the closed control. Long selections are
    /// counted rather than listed — a row that widens with every language
    /// would widen the window with it.
    private var languageSummary: String {
        let selected = RecognitionLanguage.all.filter { settings.effectiveLanguageCodes.contains($0.code) }
        switch selected.count {
        case 0: return "None"
        case 1, 2: return selected.map(\.name).joined(separator: ", ")
        default: return "\(selected[0].name), \(selected[1].name) & \(selected.count - 2) more"
        }
    }

    private var languageExplanation: String {
        let model = settings.activeModel
        let dropped = settings.unsupportedSelectedLanguages
        guard dropped.isEmpty else {
            let names = dropped.map(\.name).joined(separator: ", ")
            return "\(model.displayName) transcribes \(model.languageSummary), so \(names) is not in use. It comes back when a model that supports it is activated."
        }
        if model.supportsEveryLanguage {
            return "This model recognises \(model.supportedLanguages.count) languages."
        }
        return "\(model.displayName) recognises \(model.languageSummary)."
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.overhear.string(fromByteCount: bytes)
    }
}
