import SwiftUI

/// The catalogue half of the Transcription pane: every model Overhear can run,
/// under the heading of the engine that runs it.
///
/// Its own view rather than part of `TranscriptionSettingsView` because the
/// collapsed-engine state belongs to the list and to nothing above it.
struct AvailableModels: View {
    @ObservedObject var models: TranscriptionModelService

    /// Observed as well as the service: which model is active lives in
    /// settings, and a list that watches only the service keeps the Active mark
    /// — and the Activate and remove buttons — on whichever model was active
    /// when it last drew.
    @ObservedObject var settings: AppSettings

    /// Engines start expanded. Collapsing is for getting a long catalogue out
    /// of the way, not the state a pane should open in.
    @State private var collapsedEngines: Set<TranscriptionEngineKind> = []
    @State private var pendingRemoval: TranscriptionModel?

    var body: some View {
        ForEach(ModelCatalog.grouped(), id: \.engine) { group in
            engineGroup(group.engine, models: group.models)
        }
        .alert(item: $pendingRemoval) { model in
            Alert(
                title: Text("Remove \(model.displayName)?"),
                message: Text("This frees \(byteCount(models.diskUsage(of: model))). It can be downloaded again later."),
                primaryButton: .destructive(Text("Remove")) { models.remove(model) },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func engineGroup(_ engine: TranscriptionEngineKind, models catalogue: [TranscriptionModel]) -> some View {
        let isCollapsed = collapsedEngines.contains(engine)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation {
                    if isCollapsed {
                        collapsedEngines.remove(engine)
                    } else {
                        collapsedEngines.insert(engine)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(engine.displayName)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(collapsedSummary(engine, models: catalogue, collapsed: isCollapsed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The heading is a Text inside a Button, which VoiceOver would
            // otherwise announce as an unnamed button.
            .accessibilityLabel(engine.displayName)
            .accessibilityValue(isCollapsed ? "collapsed" : "expanded")

            if !isCollapsed {
                ForEach(catalogue) { model in
                    modelRow(model)
                        .padding(.leading, 17)
                }
            }
        }
    }

    /// What a heading says when its models are hidden. A collapsed group that
    /// holds the active model has to say so — otherwise the pane can be folded
    /// into showing nothing about what is transcribing.
    private func collapsedSummary(_ engine: TranscriptionEngineKind,
                                  models catalogue: [TranscriptionModel],
                                  collapsed: Bool) -> String {
        guard collapsed else { return engine.summary }
        if catalogue.contains(where: { isActive($0) }) {
            return "active model inside"
        }
        let downloaded = catalogue.filter { models.isDownloaded($0) }.count
        return "\(catalogue.count) models · \(downloaded) downloaded"
    }

    @ViewBuilder
    private func modelRow(_ model: TranscriptionModel) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                Text(subtitle(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            controls(for: model)
        }
    }

    /// What the right of a row offers, which is only ever one of five things:
    /// the active mark, a running download, the pair a downloaded model gets,
    /// a retry, or the download control.
    @ViewBuilder
    private func controls(for model: TranscriptionModel) -> some View {
        if isActive(model) {
            Label("Active", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.accentColor)
        } else if let fraction = models.progress[model.id] {
            ProgressView(value: fraction)
                .frame(width: 100)
            Button {
                models.cancelDownload(model)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
            .accessibilityLabel("Cancel the download of \(model.displayName)")
        } else if models.isDownloaded(model) {
            Button("Activate") { models.activate(model) }
            Button {
                pendingRemoval = model
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(model.displayName)")
            .accessibilityLabel("Remove \(model.displayName)")
        } else if models.failures[model.id] != nil {
            Button("Try Again") { models.startDownload(model) }
        } else {
            Button {
                models.startDownload(model)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Download \(model.displayName)")
            .accessibilityLabel("Download \(model.displayName)")
        }
    }

    /// The line under a model's name: what it costs, what it does, or — while
    /// something is happening to it — what is happening.
    private func subtitle(for model: TranscriptionModel) -> String {
        if let failure = models.failures[model.id] {
            return "Download failed — \(failure)"
        }
        if let fraction = models.progress[model.id] {
            let received = Int64(Double(model.downloadSize) * fraction)
            return "Downloading · \(byteCount(received)) of \(byteCount(model.downloadSize))"
        }
        var parts = [byteCount(model.downloadSize)]
        if !model.supportsEveryLanguage || model.engine != .whisper {
            parts.append(model.languageSummary)
        }
        if let note = model.note {
            parts.append(note)
        }
        return parts.joined(separator: " · ")
    }

    private func isActive(_ model: TranscriptionModel) -> Bool {
        settings.activeModelID == model.id
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.overhear.string(fromByteCount: bytes)
    }
}
