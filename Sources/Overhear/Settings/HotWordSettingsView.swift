import SwiftUI

/// Installing and removing custom cancel words.
struct HotWordSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotWordService = HotWordService.shared
    @State private var showingURLPrompt = false
    @State private var customModelURL = ""

    var body: some View {
        Form {
            Section {
                // The explanation shares the row with the picker rather than
                // sitting in the section's footer, which grouped forms render
                // outside the card.
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Cancel word", selection: $settings.cancelWord) {
                        ForEach(hotWordService.allHotWords) { word in
                            Text(word.displayName).tag(word)
                        }
                    }
                    Text("Say this word while dictating to throw away what you just said.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                if hotWordService.customHotWords.isEmpty {
                    Text("No custom Hot Words installed")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(hotWordService.customHotWords) { word in
                        HStack {
                            Text(word.displayName)
                            Spacer()
                            Button {
                                hotWordService.remove(word)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Button("Install from URL…") {
                        customModelURL = ""
                        hotWordService.downloadError = nil
                        showingURLPrompt = true
                    }
                    .disabled(hotWordService.isDownloading)
                    Button("Install from file…") {
                        hotWordService.installFromFile()
                    }
                    if hotWordService.isDownloading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    }
                }
            } header: {
                Text("Custom Hot Words")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingURLPrompt) {
            VStack(spacing: 16) {
                Text("Install Hot Word")
                    .font(.headline)
                Text("Enter the URL of an openWakeWord .onnx model file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://example.com/model.onnx", text: $customModelURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 350)
                if let error = hotWordService.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                HStack {
                    Button("Cancel") {
                        showingURLPrompt = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Download") {
                        hotWordService.downloadFromURL(customModelURL) { success in
                            if success { showingURLPrompt = false }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(customModelURL.isEmpty || hotWordService.isDownloading)
                }
            }
            .padding(20)
        }
    }
}
