import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""

    private var filteredLanguages: [WhisperLanguage] {
        if searchText.isEmpty {
            return WhisperLanguage.all
        }
        return WhisperLanguage.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recognition Languages")
                    .font(.headline)
                Text("Select which languages Whisper should recognize. Fewer languages improves accuracy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            TextField("Search languages…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List {
                ForEach(filteredLanguages) { lang in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { settings.selectedLanguageCodes.contains(lang.code) },
                            set: { isOn in
                                if isOn {
                                    settings.selectedLanguageCodes.insert(lang.code)
                                } else if settings.selectedLanguageCodes.count > 1 {
                                    settings.selectedLanguageCodes.remove(lang.code)
                                }
                            }
                        )) {
                            HStack {
                                Text(lang.name)
                                Text(lang.code)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack {
                Text("\(settings.selectedLanguageCodes.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}
