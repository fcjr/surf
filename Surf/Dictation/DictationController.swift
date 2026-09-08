// Adapted from Grumble, Copyright 2026 Left Shift Logical, LLC.
// Original code licensed under Apache-2.0; see Resources/Licenses/Grumble.txt.
// Modified for Surf: remote-driven dictation and input handling.

import AppKit
import AVFoundation
import Carbon.HIToolbox
import FluidAudio

/// Hold-to-talk speech to text: press Siri to start, release to finish. Partial transcripts are
/// typed into the focused app as they arrive, final text lands on release. Adapted from Grumble.
@MainActor
final class DictationController {
    enum State: Equatable { case idle, loadingModel, listening, finishing }
    enum ModelState: Equatable { case notLoaded, loading, loaded, failed(String) }

    private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    private(set) var modelState: ModelState = .notLoaded { didSet { onModelStateChange?(modelState) } }
    private(set) var lastTranscript = "" { didSet { onTranscript?(lastTranscript) } }
    var onStateChange: ((State) -> Void)?
    var onModelStateChange: ((ModelState) -> Void)?
    var onTranscript: ((String) -> Void)?

    private let macMic: any MicrophoneSource
    private let makeManager: () async throws -> any StreamingAsrManager
    private let injector = TextInjector()
    private var manager: (any StreamingAsrManager)?
    private var loadTask: Task<any StreamingAsrManager, Error>?
    private var pumpTask: Task<Void, Never>?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var lastPartial = ""
    private var pressed = false
    private var enabled = false
    private var startTask: Task<Void, Never>?
    private var pressID = UUID()

    static let variant: StreamingModelVariant = .parakeetUnified1120ms

    init(microphone: any MicrophoneSource = MacMicSource(),
         makeManager: @escaping () async throws -> any StreamingAsrManager = DictationController.createManager) {
        macMic = microphone
        self.makeManager = makeManager
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled {
            injector.reset()
            release()
        }
    }

    func preload() {
        Task { _ = try? await loadManagerIfNeeded() }
    }

    func press() {
        guard enabled, !pressed else { return }
        pressed = true
        pressID = UUID()
        guard startTask == nil else { return }
        let id = pressID
        startTask = Task {
            defer { startTask = nil }
            await start(id: id)
        }
    }

    func release() {
        pressed = false
        // Stop capture immediately; draining and final transcription can finish asynchronously.
        macMic.stop()
        Task { await stop() }
    }

    private func start(id: UUID) async {
        guard state == .idle || state == .loadingModel else { return }
        do {
            let manager = try await loadManagerIfNeeded()
            guard enabled, pressed, pressID == id else { return }
            await manager.setPartialTranscriptCallback { [weak self] text in
                Task { @MainActor in
                    guard let self, self.enabled, self.pressed, self.state == .listening,
                          text != self.lastPartial else { return }
                    self.lastPartial = text
                    self.lastTranscript = text
                    self.type(DictationController.stablePrefix(of: text))
                }
            }
            try await manager.reset()
            guard enabled, pressed, pressID == id else { return }
            injector.reset()
            lastPartial = ""
            let (stream, cont) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
            continuation = cont
            pumpTask = Task {
                for await buffer in stream {
                    do {
                        try await manager.appendAudio(buffer)
                        try await manager.processBufferedAudio()
                    } catch {
                        NSLog("Surf: transcription error: \(error)")
                    }
                }
            }
            try macMic.start { buffer in cont.yield(buffer) }
            state = .listening
        } catch {
            macMic.stop()
            continuation?.finish()
            continuation = nil
            pumpTask?.cancel()
            pumpTask = nil
            state = .idle
            NSLog("Surf: dictation start failed: \(error)")
        }
    }

    private func stop() async {
        guard state == .listening, let manager else { return }
        state = .finishing
        macMic.stop()
        continuation?.finish()
        continuation = nil
        await pumpTask?.value
        pumpTask = nil
        do {
            let text = try await manager.finish()
            lastTranscript = text
            if enabled { type(text) }
        } catch {
            NSLog("Surf: finish error: \(error)")
        }
        state = .idle
    }

    private func type(_ text: String) {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }
        injector.update(to: text)
    }

    private func loadManagerIfNeeded() async throws -> any StreamingAsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }
        if state == .idle { state = .loadingModel }
        modelState = .loading
        let task = Task { () throws -> any StreamingAsrManager in
            let m = try await makeManager()
            try await m.loadModels()
            return m
        }
        loadTask = task
        defer {
            loadTask = nil
            if state == .loadingModel { state = .idle }
        }
        do {
            let m = try await task.value
            manager = m
            modelState = .loaded
            return m
        } catch {
            modelState = .failed(error.localizedDescription)
            throw error
        }
    }

    private static func createManager() async throws -> any StreamingAsrManager {
        if let cfg = variant.unifiedConfig {
            let unified = StreamingUnifiedAsrManager(config: cfg)
            await unified.setProvisionalPartials(true)
            return unified
        }
        return variant.createManager()
    }

    /// Hold back the trailing in-progress word; it lands with the next partial or at finish.
    private static func stablePrefix(of text: String) -> String {
        guard let lastSpace = text.lastIndex(of: " ") else { return "" }
        return String(text[..<text.index(after: lastSpace)])
    }
}
