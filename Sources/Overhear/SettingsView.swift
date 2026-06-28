import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""
    @State private var showingURLPrompt = false
    @State private var customModelURL = ""
    @State private var isDownloading = false
    @State private var downloadError: String?

    private var selectedLanguages: [WhisperLanguage] {
        WhisperLanguage.all.filter { settings.selectedLanguageCodes.contains($0.code) }
    }

    private var filteredLanguages: [WhisperLanguage] {
        if searchText.isEmpty { return WhisperLanguage.all }
        return WhisperLanguage.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start dictating on launch", isOn: $settings.dictateOnLaunch)
                Toggle("Show overlay window during dictation", isOn: $settings.showOverlay)
                Picker("Cancel word", selection: $settings.cancelWord) {
                    ForEach(settings.allHotWords) { word in
                        Text(word.displayName).tag(word)
                    }
                }
            }

            Section {
                if settings.customHotWords.isEmpty {
                    Text("Install custom hot words to map them to different actions. Download openwakeword .onnx models to get started.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(settings.customHotWords) { word in
                        HStack {
                            Text(word.displayName)
                            Spacer()
                            Button {
                                settings.removeCustomHotWord(word)
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
                        downloadError = nil
                        showingURLPrompt = true
                    }
                    .disabled(isDownloading)
                    Button("Install from file…") {
                        installFromFile()
                    }
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    }
                }
            } header: {
                Text("Custom Hot Words")
            }

            Section {
                if selectedLanguages.isEmpty {
                    Text("No languages selected")
                        .foregroundColor(.secondary)
                } else {
                        SelectedLanguagesChips(
                        languages: selectedLanguages,
                        canRemove: settings.selectedLanguageCodes.count > 1
                    ) { code in
                        withAnimation {
                            _ = settings.selectedLanguageCodes.remove(code)
                        }
                    }
                }
            } header: {
                Text("Selected Languages")
            } footer: {
                Text("Fewer languages improves accuracy. At least one must be selected.")
            }

            Section("Languages") {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ForEach(filteredLanguages) { lang in
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
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .sheet(isPresented: $showingURLPrompt) {
            VStack(spacing: 16) {
                Text("Install Hot Word")
                    .font(.headline)
                Text("Enter the URL of an openwakeword .onnx model file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://example.com/model.onnx", text: $customModelURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 350)
                if let error = downloadError {
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
                        downloadCustomModel()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(customModelURL.isEmpty || isDownloading)
                }
            }
            .padding(20)
        }
    }

    private func installFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "onnx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select an openwakeword .onnx model file"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let modelsDir = HotWord.modelsDirectory
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        let destURL = modelsDir.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            settings.reloadCustomHotWords()
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func downloadCustomModel() {
        guard let url = URL(string: customModelURL) else {
            downloadError = "Invalid URL"
            return
        }
        guard url.pathExtension.lowercased() == "onnx" else {
            downloadError = "URL must point to an .onnx file"
            return
        }
        isDownloading = true
        downloadError = nil

        let modelsDir = HotWord.modelsDirectory
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            DispatchQueue.main.async {
                isDownloading = false
                if let error {
                    downloadError = error.localizedDescription
                    return
                }
                guard let tempURL else {
                    downloadError = "Download failed"
                    return
                }
                let filename = url.lastPathComponent
                let destURL = modelsDir.appendingPathComponent(filename)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    settings.reloadCustomHotWords()
                    showingURLPrompt = false
                } catch {
                    downloadError = error.localizedDescription
                }
            }
        }.resume()
    }
}

struct SelectedLanguagesChips: View {
    let languages: [WhisperLanguage]
    let canRemove: Bool
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(languages) { lang in
                LanguageChip(language: lang, canRemove: canRemove) {
                    onRemove(lang.code)
                }
            }
        }
    }
}

struct LanguageChip: View {
    let language: WhisperLanguage
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(language.flag)
                .font(.system(size: 12))
            Text(language.name)
                .font(.system(size: 12, weight: .medium))
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var yOffset = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var xOffset = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: xOffset, y: yOffset), proposal: ProposedViewSize(size))
                xOffset += size.width + spacing
            }
            yOffset += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
