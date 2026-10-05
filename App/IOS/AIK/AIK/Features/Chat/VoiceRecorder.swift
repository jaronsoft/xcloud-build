import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    func toggle() async -> URL? {
        if isRecording {
            return stop()
        }
        await start()
        return nil
    }

    func start() async {
        errorMessage = nil
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard granted else {
            errorMessage = String(localized: "voice.permission_denied")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("aik-voice-\(UUID().uuidString).m4a")
            recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            )
            recorder?.delegate = self
            recorder?.record()
            startedAt = Date()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        defer {
            self.recorder = nil
            startedAt = nil
        }
        guard let startedAt, Date().timeIntervalSince(startedAt) >= 0.8 else {
            try? FileManager.default.removeItem(at: recorder.url)
            errorMessage = String(localized: "voice.too_short")
            return nil
        }
        return recorder.url
    }

    func clearError() {
        errorMessage = nil
    }
}
