import SwiftUI

/// The language multi-select: a search field over every language the active
/// model supports, ticked in place.
///
/// A popover rather than a menu because it has to stay open across ticks and
/// carry a search field — picking five languages should not mean opening the
/// same menu five times, and a menu cannot hold a text field.
struct LanguagePicker: View {
    @ObservedObject var settings: AppSettings
    @State private var searchText = ""

    private var matches: [WhisperLanguage] {
        guard !searchText.isEmpty else { return ordered }
        return ordered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Selected first, so what is in use is not somewhere down a list of
    /// ninety-nine.
    private var ordered: [WhisperLanguage] {
        let selected = settings.effectiveLanguageCodes
        return WhisperLanguage.all.sorted { lhs, rhs in
            let left = selected.contains(lhs.code)
            let right = selected.contains(rhs.code)
            if left != right { return left }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { language in
                        row(language)
                    }
                }
            }
            .frame(height: 240)

            Text("At least one language stays selected. Fewer languages improves accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder
    private func row(_ language: WhisperLanguage) -> some View {
        let supported = settings.activeModel.supports(language.code)
        let isOn = settings.effectiveLanguageCodes.contains(language.code)

        Toggle(isOn: Binding(
            get: { isOn },
            set: { on in
                withAnimation {
                    if on {
                        settings.selectedLanguageCodes.insert(language.code)
                    } else if settings.effectiveLanguageCodes.count > 1 {
                        settings.selectedLanguageCodes.remove(language.code)
                    }
                }
            }
        )) {
            HStack(spacing: 6) {
                Text(language.flag)
                Text(language.name)
                Spacer()
                Text(language.code)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.checkbox)
        // Unsupported languages are dimmed in place rather than dropped, so a
        // user on an English-only model can see what activating a multilingual
        // one would give them back.
        .disabled(!supported)
        .foregroundStyle(supported ? .primary : .tertiary)
        .help(supported ? "" : "\(settings.activeModel.displayName) cannot transcribe \(language.name)")
    }
}
