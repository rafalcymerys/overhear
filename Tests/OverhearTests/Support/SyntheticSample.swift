import AVFoundation
import XCTest
@testable import Overhear

/// The recordings in `Specs/Fixtures/Synthetic`, by the names the specs use.
///
/// They live outside the test bundle because the specs refer to them too, so
/// they are loaded by path rather than through `Bundle.module`.
enum SyntheticSample: String, CaseIterable {
    case helloEn = "HelloEn"
    case sentenceEn = "SentenceEn"
    case paragraphEn = "ParagraphEn"
    case monologueEn = "MonologueEn"
    case dzienDobryPl = "DzienDobryPl"
    case sentencePl = "SentencePl"
    case paragraphPl = "ParagraphPl"
    case gutenTagDe = "GutenTagDe"
    case bonjourFr = "BonjourFr"
    case alexa = "Alexa"
    case heyJarvis = "HeyJarvis"
    case sentenceThenAlexa = "SentenceThenAlexa"
    case alexaDuringTranscription = "AlexaDuringTranscription"
    case coughing = "Coughing"
    case silence = "Silence"
    case backgroundNoise = "BackgroundNoise"
    case quietEn = "QuietEn"
    case mixedEnPl = "MixedEnPl"

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // OverhearTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Specs/Fixtures/Synthetic")
    }

    var url: URL {
        Self.directory.appendingPathComponent("\(rawValue).wav")
    }

    /// Samples in the -1...1 range the engine works in.
    func load() throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 16000, "\(rawValue) is not 16 kHz")
        XCTAssertEqual(file.processingFormat.channelCount, 1, "\(rawValue) is not mono")

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        return (0..<Int(buffer.frameLength)).map { channel[$0] }
    }

    /// Scaled to int16 range, which is what the wake word models expect.
    func loadForDetector() throws -> [Float] {
        try load().map { $0 * 32767 }
    }

    var duration: TimeInterval {
        get throws {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        }
    }

    /// Mean absolute amplitude, against the engine's silence threshold.
    func meanLevel() throws -> Float {
        let audio = try load()
        guard !audio.isEmpty else { return 0 }
        return audio.reduce(0) { $0 + abs($1) } / Float(audio.count)
    }
}
