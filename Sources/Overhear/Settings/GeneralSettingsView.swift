import SwiftUI

/// How Overhear behaves on launch and while listening.
struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Start listening on launch", isOn: $settings.dictateOnLaunch)
                Toggle("Show overlay window while listening", isOn: $settings.showOverlay)
                HotkeyRecorderRow()
                // Under the row, because it says what that combination does.
                // Offered whether or not one is recorded: it describes the mode
                // the app is in, and the row above is where a combination is
                // given to that mode.
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
            } header: {
                Text("Transcription")
            }
        }
        .formStyle(.grouped)
    }
}
