import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""

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
