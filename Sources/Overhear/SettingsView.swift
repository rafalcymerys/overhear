import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""

    private var selectedLanguages: [WhisperLanguage] {
        WhisperLanguage.all.filter { settings.selectedLanguageCodes.contains($0.code) }
    }

    private var availableLanguages: [WhisperLanguage] {
        let languages = WhisperLanguage.all.filter { !settings.selectedLanguageCodes.contains($0.code) }
        if searchText.isEmpty { return languages }
        return languages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show overlay window during dictation", isOn: $settings.showOverlay)
            }

            Section {
                ForEach(selectedLanguages) { lang in
                    languageRow(lang, selected: true)
                }
            } header: {
                Text("Selected Languages")
            } footer: {
                Text("Fewer languages improves accuracy. At least one must be selected.")
            }

            Section("Available Languages") {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ForEach(availableLanguages) { lang in
                    languageRow(lang, selected: false)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }

    private func languageRow(_ lang: WhisperLanguage, selected: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { settings.selectedLanguageCodes.contains(lang.code) },
            set: { isOn in
                withAnimation {
                    if isOn {
                        settings.selectedLanguageCodes.insert(lang.code)
                    } else if settings.selectedLanguageCodes.count > 1 {
                        settings.selectedLanguageCodes.remove(lang.code)
                    }
                }
            }
        )) {
            HStack {
                Text(lang.flag)
                Text(lang.name)
                Text(lang.code)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
