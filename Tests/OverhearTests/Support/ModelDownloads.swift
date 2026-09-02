import FluidAudio
import Foundation
import XCTest
@testable import Overhear

/// What a finished download leaves behind, in whichever layout the engine that
/// fetched it uses. Tests inject a downloader that calls this instead of
/// reaching the network.
enum FakeModelDownload {
    static func write(_ model: TranscriptionModel,
                      into base: URL,
                      includingVocabulary: Bool = true) {
        let folder: URL
        var parts: [String]

        switch model.engine {
        case .whisper:
            folder = base
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent("openai_whisper-\(model.variant)")
            parts = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
        case .parakeet:
            folder = base.appendingPathComponent(model.variant)
            // Asked of the library rather than spelled out, so a rename upstream
            // fails the test that pins it rather than every test here.
            parts = Array(ModelNames.ASR.requiredModelsV3(precision: ParakeetVariant.encoderPrecision))
            if includingVocabulary {
                parts.append(ModelNames.ASR.vocabularyFile)
            }
        }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for part in parts {
            try? Data(repeating: 7, count: 4096).write(to: folder.appendingPathComponent(part))
        }
    }
}

extension OverhearTestCase {
    /// A service over the test's own temporary directory, with the network
    /// replaced by a downloader that writes what a finished download would.
    @MainActor
    func makeModelService(download: TranscriptionModelService.Downloader? = nil,
                          settings: AppSettings? = nil) -> TranscriptionModelService {
        TranscriptionModelService(
            rootDirectory: tempDirectory,
            settings: settings ?? AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn),
            download: download ?? { model, base, report in
                report(1)
                FakeModelDownload.write(model, into: base)
            }
        )
    }

    /// Wait for whatever the service is doing to a model to finish.
    @MainActor
    func settle(_ service: TranscriptionModelService, _ model: TranscriptionModel) async {
        await waitUntil("\(model.displayName) settles") { !service.isDownloading(model) }
    }
}

enum ModelTestError: Error, LocalizedError {
    case offline
    var errorDescription: String? { "The network connection was lost." }
}

/// A one-shot signal, for a download that has to be caught mid-flight.
actor DownloadStarted {
    private var fulfilled = false
    func fulfil() { fulfilled = true }
    func wait() async {
        while !fulfilled { await Task.yield() }
    }
}
