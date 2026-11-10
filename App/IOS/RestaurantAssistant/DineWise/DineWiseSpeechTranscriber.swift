import AVFoundation
import Speech
import SwiftUI

private func dineWiseSpeechPrefix(_ text: String, maximumUTF16Length: Int) -> (value: String, truncated: Bool) {
    var value = ""
    var remaining = max(0, maximumUTF16Length)
    for character in text {
        let units = String(character).utf16.count
        guard units <= remaining else { return (value, true) }
        value.append(character)
        remaining -= units
    }
    return (value, false)
}

@MainActor
final class DineWiseSpeechTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published var transcription = ""
    @Published private(set) var message = ""

    private var audioEngine: AVAudioEngine?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration = 0
    private var isStoppingAudio = false

    func toggle() {
        if isRecording {
            stopRecording()
        } else {
            recognitionGeneration += 1
            let generation = recognitionGeneration
            Task { await beginRecording(generation: generation) }
        }
    }

    func stop() {
        recognitionGeneration += 1
        guard !isPreparing else { return }
        Task { await stopAudioCapture() }
    }

    private func beginRecording(generation: Int) async {
        guard !isPreparing, !isRecording, !isStoppingAudio else { return }
        guard let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            message = "当前设备不支持离线中文语音识别，仍可直接键入。"
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        guard await requestSpeechAuthorization() else {
            guard generation == recognitionGeneration else { return }
            message = "语音识别权限未开启，仍可直接键入。"
            return
        }
        guard await requestMicrophonePermission() else {
            guard generation == recognitionGeneration else { return }
            message = "麦克风权限未开启，仍可直接键入。"
            return
        }
        guard generation == recognitionGeneration else { return }

        do {
            try await setAudioSessionCategory()
            try await setAudioSessionActive(true)
            guard generation == recognitionGeneration else {
                await stopAudioCapture()
                return
            }

            let engine = AVAudioEngine()
            audioEngine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
                buffer, _ in request.append(buffer)
            }
            recognitionRequest = request
            transcription = ""
            message = "请开始说话；结束后核对转写文字。"
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.recognitionGeneration == generation else { return }
                    if let result {
                        let limited = dineWiseSpeechPrefix(result.bestTranscription.formattedString,
                                                           maximumUTF16Length: 4000)
                        self.transcription = limited.value
                        if limited.truncated {
                            self.message = "语音转写达到 4,000 字上限，后续内容未加入；请分段转写。"
                        }
                        if result.isFinal {
                            if !limited.truncated { self.message = "请核对转写内容，再加入原始资料。" }
                            await self.stopAudioCapture()
                        }
                    }
                    if error != nil {
                        self.message = self.transcription.isEmpty
                            ? "语音转写未完成，可直接键入原始资料。"
                            : "转写已停止，请核对现有文字。"
                        await self.stopAudioCapture()
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            await stopAudioCapture()
            if generation == recognitionGeneration {
                message = "无法启动离线语音转写，可直接键入原始资料。"
            }
        }
    }

    private func stopRecording() {
        Task { await stopAudioCapture() }
        if !transcription.isEmpty { message = "请核对转写内容，再加入原始资料。" }
    }

    private func stopAudioCapture() async {
        guard !isStoppingAudio else { return }
        isStoppingAudio = true
        defer { isStoppingAudio = false }
        let engine = audioEngine
        audioEngine = nil
        if engine?.isRunning == true { engine?.stop() }
        engine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
        try? await setAudioSessionActive(false)
    }

    private func setAudioSessionActive(_ active: Bool) async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            if active {
                _ = try await session.activate(options: [])
            } else {
                _ = try await session.deactivate(options: .notifyOthersOnDeactivation)
            }
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setAudioSessionCategory() async throws {
        let session = AVAudioSession.sharedInstance()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
