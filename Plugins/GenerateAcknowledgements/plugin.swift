import Foundation
import PackagePlugin

/// Builds the third-party license notice that ships inside `Overhear.app`.
///
/// MIT and Apache-2.0 §4 both require the license text to travel with a binary
/// distribution, so the notice has to be built from whatever is actually
/// resolved rather than written by hand — a hand-written list drifts the first
/// time someone bumps a dependency and forgets.
///
/// Running as a build tool plugin rather than as a step in `scripts/build.sh`
/// is what keeps a development build, `swift test` and the packaged app reading
/// the same file: SwiftPM treats the generated text as a resource of the
/// `Overhear` target, so `Bundle.module` finds it in all three. The packaged app
/// gets it for free too — the generated resource bundle is one of the
/// `.build/release/*.bundle` directories `build.sh` already copies into
/// `Contents/Resources`.
@main
struct GenerateAcknowledgements: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let manifestPath = context.package.directory.appending(["Resources", "acknowledgements.json"])
        let preamblePath = context.package.directory.appending(["Resources", "acknowledgements-preamble.txt"])
        let scriptPath = context.package.directory.appending(["scripts", "generate-acknowledgements.sh"])

        let manifest = try Manifest(contentsOf: manifestPath)
        let resolved = resolvedPackages(of: context.package)

        guard let shipping = reconcile(manifest: manifest, against: resolved, manifestPath: manifestPath) else {
            // `reconcile` has already emitted the specifics. Returning no
            // commands rather than throwing keeps the error readable: the
            // diagnostics are the message, and a thrown error would bury them
            // under a plugin stack trace.
            return []
        }

        let output = context.pluginWorkDirectory.appending("Acknowledgements.txt")
        let licenseFiles = shipping.flatMap(\.licenseFiles)

        return [
            .buildCommand(
                displayName: "Generating Acknowledgements.txt",
                executable: Path("/bin/bash"),
                arguments: [scriptPath.string, output.string, preamblePath.string]
                    + shipping.map(\.commandArgument),
                // Everything the text is derived from, so the command re-runs
                // when a dependency moves and stays cached when nothing has.
                inputFiles: [scriptPath, manifestPath, preamblePath] + licenseFiles,
                outputFiles: [output]
            )
        ]
    }

    // MARK: - The resolved graph

    /// Every package Overhear resolves, direct and transitive, keyed by identity.
    ///
    /// Read from the plugin context rather than by parsing `Package.resolved`,
    /// which would also mean guessing that checkouts live in `.build/checkouts`
    /// — untrue under a custom scratch path.
    private func resolvedPackages(of root: Package) -> [String: Package] {
        var found: [String: Package] = [:]

        func walk(_ package: Package) {
            for dependency in package.dependencies {
                let resolved = dependency.package
                guard found[resolved.id] == nil else { continue }
                found[resolved.id] = resolved
                walk(resolved)
            }
        }

        walk(root)
        return found
    }

    // MARK: - Reconciliation

    /// The packages to write license text for, or nil if the manifest and the
    /// resolved graph disagree.
    ///
    /// Disagreeing is a build failure on purpose. A dependency added without a
    /// line in the manifest is exactly the drift this plugin exists to catch,
    /// and catching it at build time means it surfaces on the branch that
    /// introduced it rather than at the next release.
    private func reconcile(manifest: Manifest,
                           against resolved: [String: Package],
                           manifestPath: Path) -> [ShippingPackage]? {
        var failed = false

        for identity in resolved.keys.sorted() where manifest.packages[identity] == nil {
            Diagnostics.error("""
                \(identity) is resolved but not classified in \(manifestPath.string). \
                Add an entry saying whether it ships inside Overhear.app, so its license \
                travels with the binary if it does.
                """)
            failed = true
        }

        for identity in manifest.packages.keys.sorted() where resolved[identity] == nil {
            Diagnostics.error("""
                \(manifestPath.string) classifies \(identity), which is no longer resolved. \
                Remove the entry.
                """)
            failed = true
        }

        var shipping: [ShippingPackage] = []

        for (identity, entry) in manifest.packages.sorted(by: { $0.key < $1.key }) {
            guard entry.ships, let package = resolved[identity] else { continue }

            let licenseFiles = noticeFiles(in: package.directory)
            guard !licenseFiles.isEmpty else {
                Diagnostics.error("""
                    \(identity) ships inside Overhear.app but has no LICENSE or NOTICE file \
                    in \(package.directory.string). Distributing it without its license text \
                    is what this file exists to prevent.
                    """)
                failed = true
                continue
            }

            shipping.append(ShippingPackage(displayName: entry.name,
                                            version: version(of: package),
                                            url: url(of: package),
                                            licenseFiles: licenseFiles))
        }

        return failed ? nil : shipping
    }

    /// A package's `LICENSE*` and `NOTICE*` files, in that order.
    ///
    /// NOTICE is picked up by the same rule rather than named for the two
    /// packages that currently have one — Apache-2.0 §4(d) requires it wherever
    /// it appears, and swift-crypto's in particular records vendored
    /// derivations that its LICENSE alone doesn't mention.
    private func noticeFiles(in directory: Path) -> [Path] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.string)) ?? []
        return names
            .filter { name in
                let lowercased = name.lowercased()
                return lowercased.hasPrefix("license") || lowercased.hasPrefix("notice")
            }
            .sorted()
            .map { directory.appending($0) }
    }

    private func version(of package: Package) -> String {
        switch package.origin {
        case .repository(_, let displayVersion, _): return displayVersion
        case .registry(_, let displayVersion): return displayVersion
        case .local, .root: return ""
        @unknown default: return ""
        }
    }

    private func url(of package: Package) -> String {
        switch package.origin {
        case .repository(let url, _, _): return url
        case .registry, .local, .root: return ""
        @unknown default: return ""
        }
    }

    // MARK: - Types

    private struct ShippingPackage {
        let displayName: String
        let version: String
        let url: String
        let licenseFiles: [Path]

        /// One package per argument, tab-separated — paths cannot contain tabs,
        /// and a single argument per package keeps the script's parsing to one
        /// `read -ra`.
        var commandArgument: String {
            ([displayName, version, url] + licenseFiles.map(\.string)).joined(separator: "\t")
        }
    }

}

/// `Resources/acknowledgements.json`: what each resolved package is, and
/// whether it ships inside the app.
private struct Manifest: Decodable {
    let packages: [String: ManifestEntry]

    init(contentsOf path: Path) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
        self = try JSONDecoder().decode(Manifest.self, from: data)
    }
}

private struct ManifestEntry: Decodable {
    let name: String
    let ships: Bool
}
