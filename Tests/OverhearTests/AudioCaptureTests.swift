import AVFoundation
import XCTest
@testable import Overhear

/// Opens the real microphone. Skipped by default — CI has no input device, and
/// on a developer's Mac it needs the test runner to hold microphone permission.
/// Run it with `OVERHEAR_RUN_AUDIO_TESTS=1 swift test --filter AudioCaptureTests`.
final class AudioCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OVERHEAR_RUN_AUDIO_TESTS"] == "1",
            "set OVERHEAR_RUN_AUDIO_TESTS=1 to run tests that open the microphone"
        )
        // Microphone access is granted per binary, and the test runner is a new
        // binary after every build touching this target. Without the grant
        // AVAudioEngine still starts and simply never delivers a buffer, which
        // would surface as a watchdog timeout and read like a bug in
        // AudioCapture rather than a missing permission.
        try XCTSkipUnless(
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            "the test runner does not hold microphone permission (status: \(Self.authorizationName))"
        )
    }

    private static var authorizationName: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    /// The contract the rest of the engine is built on: a steady stream of
    /// chunks of exactly the size the wake word models expect, arriving in
    /// roughly real time even when nobody is speaking.
    func testDeliversFixedSizeChunksInRealTime() async throws {
        let capture = AudioCapture()
        defer { capture.stop() }

        var chunks = 0
        let started = ContinuousClock.now

        for await event in capture.events() {
            switch event {
            case .chunk(let chunk):
                XCTAssertEqual(chunk.count, WakeWordDetector.chunkSamples)
                chunks += 1
            case .interrupted(let reason):
                XCTFail("capture was interrupted: \(reason)")
                return
            }
            if chunks >= 25 { break }
        }

        let elapsed = ContinuousClock.now - started
        XCTAssertEqual(chunks, 25)
        // 25 chunks is two seconds of audio; anything much faster means the
        // chunking is wrong rather than the microphone being quick.
        XCTAssertGreaterThan(elapsed, .seconds(1.5))
        XCTAssertLessThan(elapsed, .seconds(6))
    }
}
