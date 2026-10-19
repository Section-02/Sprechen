import AVFoundation
import Speech
import SwiftUI

@MainActor
final class SpeechController: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isStarting = false
    @Published var message: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var generation = UUID()

    func start(direction: Pool) async {
        guard !isRecording && !isStarting else { return }
        stop()
        let token = UUID(); generation = token
        isStarting = true; transcript = ""; message = nil
        defer { if generation == token { isStarting = false } }
        let locale = Locale(identifier: direction == .englishToGerman ? "de-DE" : "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            message = "On-device speech isn’t available for this language on this iPhone. You can still reveal and grade your answer."; return
        }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token else { return }
        guard authorization == .authorized else { message = "Allow Speech Recognition in iPhone Settings to use the microphone."; return }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == token else { return }
        guard mic else { message = "Allow Microphone access in iPhone Settings to speak your answer."; return }
        guard recognizer.isAvailable else { message = "Speech recognition is unavailable right now. Try again or study silently."; return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true // Never fall back to a server.
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw SprechenError.message("The microphone is unavailable.") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            self.engine = engine; self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let errorText = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let text { self.transcript = text }
                    if final || errorText != nil {
                        let wasRecording = self.isRecording
                        self.stop()
                        if errorText != nil && wasRecording && self.transcript.isEmpty {
                            self.message = "Couldn’t transcribe locally. Try again or grade your answer yourself."
                        }
                    }
                }
            }
            engine.prepare(); try engine.start(); isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
        } catch { stop(); message = error.localizedDescription }
    }
    func finish() {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); isRecording = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stop() {
        generation = UUID(); isStarting = false
        timer?.invalidate(); timer = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); task?.cancel(); request = nil; task = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func clear() { stop(); transcript = ""; message = nil }
}
