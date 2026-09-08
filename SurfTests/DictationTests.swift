import AVFoundation
import FluidAudio
import XCTest

@MainActor
final class DictationTests: XCTestCase {
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for dictation state")
    }

    func testDisablingDictationStopsCaptureImmediately() async throws {
        let mic = FakeMicrophone()
        let manager = FakeRecognizer()
        let controller = DictationController(microphone: mic, makeManager: { manager })
        controller.setEnabled(true)
        controller.press()
        try await waitUntil { controller.state == .listening }
        XCTAssertTrue(mic.running)
        controller.setEnabled(false)
        XCTAssertFalse(mic.running)
        try await waitUntil { controller.state == .idle }
        controller.press()
        await Task.yield()
        XCTAssertEqual(mic.starts, 1)
    }

    func testReleaseWhileRecognizerIsResettingDoesNotStartCapture() async throws {
        let mic = FakeMicrophone()
        let manager = FakeRecognizer(pauseReset: true)
        let controller = DictationController(microphone: mic, makeManager: { manager })
        controller.setEnabled(true)
        controller.press()
        try await waitUntil { await manager.waitingForReset }
        controller.release()
        await manager.resumeReset()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(mic.starts, 0)
        XCTAssertFalse(mic.running)
    }

    func testDisconnectReleasesDictation() async throws {
        let mic = FakeMicrophone()
        let manager = FakeRecognizer()
        let controller = DictationController(microphone: mic, makeManager: { manager })
        controller.setEnabled(true)
        let held = HeldActions()
        held.perform = { action, down in
            guard action == .dictation else { return }
            if down { controller.press() } else { controller.release() }
        }
        held.update(remote: "remote", button: .siri, action: .dictation, down: true)
        try await waitUntil { controller.state == .listening }
        held.retainConnected([])
        XCTAssertFalse(mic.running)
        try await waitUntil { controller.state == .idle }
    }

    func testMicrophoneFailureCanBeRetried() async throws {
        let mic = FakeMicrophone()
        mic.fail = true
        let manager = FakeRecognizer()
        let controller = DictationController(microphone: mic, makeManager: { manager })
        controller.setEnabled(true)
        controller.press()
        try await waitUntil { mic.starts == 1 && controller.state == .idle }
        controller.release()
        await Task.yield()
        mic.fail = false
        controller.press()
        try await waitUntil { controller.state == .listening }
        XCTAssertTrue(mic.running)
        controller.setEnabled(false)
        try await waitUntil { controller.state == .idle }
    }
}

private final class FakeMicrophone: MicrophoneSource {
    var running = false
    var starts = 0
    var fail = false
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        starts += 1
        if fail { throw NSError(domain: "test", code: 1) }
        running = true
    }
    func stop() { running = false }
}

private actor FakeRecognizer: StreamingAsrManager {
    var displayName: String { "Test recognizer" }
    var waitingForReset: Bool { resetContinuation != nil }
    private let pauseReset: Bool
    private var resetContinuation: CheckedContinuation<Void, Never>?
    init(pauseReset: Bool = false) { self.pauseReset = pauseReset }
    func loadModels() async throws {}
    func appendAudio(_ buffer: AVAudioPCMBuffer) throws {}
    func processBufferedAudio() async throws {}
    func finish() async throws -> String { "" }
    func reset() async throws {
        if pauseReset { await withCheckedContinuation { resetContinuation = $0 } }
    }
    func resumeReset() {
        resetContinuation?.resume()
        resetContinuation = nil
    }
    func cleanup() async {}
    func setPartialTranscriptCallback(_ callback: @escaping @Sendable (String) -> Void) {}
    func getPartialTranscript() -> String { "" }
}
