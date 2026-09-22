import SwiftUI
import Speech
import AVFoundation
import Accelerate

/// The audio callback only writes a small meter value. UI samples it at 10 Hz.
private final class SpeechMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func capture(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        let normalized = max(0, min(1, (20 * log10(max(rms, 0.00001)) + 55) / 45))
        lock.lock(); value = normalized; lock.unlock()
    }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return Double(value) }
}

@MainActor
final class SpeechActivity: ObservableObject {
    @Published var level = 0.0
}

@MainActor
final class SpeechInput: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var requesting = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?
    let activity = SpeechActivity()
    @Published private(set) var elapsed = 0
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var accumulated = DictationTranscript()
    private var token = UUID()
    private var utteranceToken = UUID()
    private var timeout: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?

    func reset() {
        stop(); error = nil; transcript = ""; accumulated = DictationTranscript(); elapsed = 0
    }
    func start() {
        reset(); requesting = true
        let id = token
        Task { [weak self] in
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard let self, id == self.token else { return }
            guard authorization == .authorized else { self.requesting = false; self.error = "Разреши распознавание речи для «Тарелки» в настройках конфиденциальности macOS. Можно также ввести продукты текстом."; return }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")), recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else {
                self.requesting = false; self.error = "На этом Mac локальное распознавание русской речи пока недоступно. Введи список текстом или используй системную диктовку macOS в поле продуктов."; return
            }
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard id == self.token else { return }
            guard allowed else { self.requesting = false; self.error = "Доступ к микрофону выключен. Разреши его для «Тарелки» в настройках macOS."; return }
            self.recognizer = recognizer
            do {
                try self.listen(session: id)
                self.recording = true; self.requesting = false
                self.timeout = Task { [weak self] in
                    for second in 1...60 {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        guard let self, self.token == id else { return }
                        self.elapsed = second
                    }
                    self?.stop()
                }
            } catch { self.stop(); self.error = error.localizedDescription }
        }
    }

    private func listen(session id: UUID) throws {
        guard let recognizer else { return }
        let engine = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest(), meter = SpeechMeter()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.noMicrophone }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["картошка", "яйца", "помидоры", "творог", "гречка", "курица"]
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer); meter.capture(buffer)
        }
        self.engine = engine; self.request = request
        let utterance = UUID(); utteranceToken = utterance
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            let text = result?.bestTranscription.formattedString
            let segments = result?.bestTranscription.segments
            let metadata = result?.speechRecognitionMetadata
            let start = metadata?.speechStartTimestamp ?? segments?.first?.timestamp
            let end = metadata.map { $0.speechStartTimestamp + $0.speechDuration }
                ?? segments?.last.map { $0.timestamp + $0.duration }
            let completed = metadata != nil
            let final = result?.isFinal == true
            let message = failure?.localizedDescription
            Task { @MainActor in
                guard let self, self.token == id, self.utteranceToken == utterance else { return }
                if let text {
                    self.accumulated.update(text, start: start, end: end, completed: completed || final)
                    self.transcript = self.accumulated.text
                }
                if let message {
                    self.stop(); self.error = "Распознавание остановилось. Уже записанные продукты сохранены. \(message)"
                } else if final {
                    // A recognizer can finish after silence. Keep the user session
                    // open and retain completed phrases when beginning the next request.
                    self.accumulated.finishUtterance()
                    self.releaseAudio()
                    do { try self.listen(session: id) }
                    catch { self.stop(); self.error = error.localizedDescription }
                }
            }
        }
        engine.prepare(); try engine.start()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.token == id, self.utteranceToken == utterance else { return }
                self.activity.level = meter.read()
            }
        }
    }
    private func releaseAudio() {
        utteranceToken = UUID(); meterTask?.cancel(); meterTask = nil
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil; request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
        activity.level = 0
    }
    func stop() {
        token = UUID(); timeout?.cancel(); timeout = nil
        releaseAudio(); recognizer = nil
        recording = false; requesting = false
    }
    enum SpeechError: LocalizedError {
        case noMicrophone
        var errorDescription: String? { "Не найден работающий микрофон. Проверь устройство ввода в настройках звука macOS." }
    }
}
