import SwiftUI

/// How Overhear behaves on launch and while listening.
struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show overlay window while listening", isOn: $settings.showOverlay)
            }

            Section {
                // The choice first: the row under it means nothing until the
                // mode has said what a press is worth.
                Picker("", selection: $settings.listeningMode) {
                    ForEach(ListeningMode.allCases) { mode in
                        // The explanation rides with the option it describes,
                        // the way each transcription setting's does.
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                            Text(mode.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                HotkeyRecorderRow()

                // Shown in both modes and enabled in one. Hold to talk has no
                // key held at launch, and no **Stop Listening** to reach the
                // session it would start with — but a toggle that vanished
                // would take its value with it, and it is kept rather than
                // forgotten.
                Toggle("Start listening on launch", isOn: $settings.dictateOnLaunch)
                    .disabled(settings.listeningMode == .holdToTalk)
            } header: {
                Text("Listening Mode")
            }

            Section {
                // The explanation sits in the row with the toggle rather than in
                // the section's footer, which grouped forms render outside the
                // card — this keeps it attached to the control it describes.
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Strip transcription annotations", isOn: $settings.stripAnnotations)
                    Text("The transcription model sometimes adds annotations like (coughing).\nTurn on to remove it from what gets pasted into your app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Ensure spaces around inserted text", isOn: $settings.spaceInsertedText)
                    Text("When transcribing text next to an existing sentence, make sure that there is a space around what you've just dictated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Transcription")
            }
        }
        .formStyle(.grouped)
    }
}
