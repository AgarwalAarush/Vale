import AppKit
@preconcurrency import AVFoundation
import Speech

@MainActor final class VoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var listening = false
    @Published var speaking = false
    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var activeUtterance: AVSpeechUtterance?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var hasTap = false
    private var silence: DispatchWorkItem?
    private var finalText = ""
    private var generation = UUID()
    var partial: ((String) -> Void)?
    var finished: ((String) -> Void)?
    var failed: ((String) -> Void)?
    override init() { super.init(); synth.delegate = self }
    func start() {
        stopSpeaking()
        let id = UUID(); generation = id
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard self.generation == id else { return }
                guard status == .authorized else { self.failed?("Speech access is off. Enable it in System Settings, or keep typing."); return }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard self.generation == id else { return }
                        guard granted else { self.failed?("Microphone access is off. Enable it in System Settings, or keep typing."); return }
                        self.beginRecognition()
                    }
                }
            }
        }
    }

    private func beginRecognition() {
        stopListening()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { failed?("Speech recognition is unavailable. You can still type."); return }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request; finalText = ""
        let id = UUID(); generation = id
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { failed?("No microphone is available. You can still type."); return }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                guard self.generation == id, self.listening else { return }
                if let result {
                    self.finalText = result.bestTranscription.formattedString; self.partial?(self.finalText)
                    self.silence?.cancel()
                    let item = DispatchWorkItem { [weak self] in self?.finishUtterance() }
                    self.silence = item; DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
                    if result.isFinal { self.finishUtterance() }
                } else if error != nil {
                    self.stopListening(); self.failed?("Dictation stopped. Your draft is preserved; send it or try again.")
                }
            }
        }
        do { engine.prepare(); try engine.start(); listening = true }
        catch { stopListening(); failed?("Couldn’t start the microphone. You can still type.") }
    }
    func finishUtterance() {
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        if !text.isEmpty { finished?(text) }
    }
    func stopListening() {
        generation = UUID(); silence?.cancel(); silence = nil
        if engine.isRunning { engine.stop() }
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; recognizer = nil; listening = false
    }
    func speak(_ text: String) {
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: text.replacingOccurrences(of: "`", with: ""))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.rate = 0.49
        activeUtterance = utterance; speaking = true; synth.speak(utterance)
    }
    func stopSpeaking() { activeUtterance = nil; synth.stopSpeaking(at: .immediate); speaking = false }
    func stop() { stopListening(); stopSpeaking() }
    nonisolated private func playbackEnded(_ utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            guard let self, let active = self.activeUtterance, ObjectIdentifier(active) == identity else { return }
            self.activeUtterance = nil; self.speaking = false
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { playbackEnded(utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { playbackEnded(utterance) }
}
