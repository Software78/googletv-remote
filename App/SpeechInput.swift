import Foundation
import Speech
import AVFoundation

/// Live speech-to-text from the phone's microphone. The transcript is sent to the TV as typed text.
@MainActor @Observable
final class SpeechInput {
    enum State: Equatable { case idle, listening, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard state != .listening else { return }
        transcript = ""
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { state = .denied; return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            Self.installTap(on: input, request: req)
            engine.prepare()
            try engine.start()
            task = Self.makeTask(recognizer, req) { [weak self] text in
                Task { @MainActor in
                    guard let self, self.state == .listening, let text else { return }
                    self.transcript = text
                }
            }
            state = .listening
        } catch {
            stopEngine()
            state = .unavailable
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        guard state == .listening else { return "" }
        stopEngine()
        state = .idle
        let heard = transcript
        transcript = ""
        return heard
    }

    private func stopEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Nonisolated: these closures run on audio / speech threads.
    nonisolated private static func installTap(on node: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func makeTask(_ r: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                             onText: @escaping @Sendable (String?) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: req) { result, _ in
            onText(result?.bestTranscription.formattedString)
        }
    }
}
