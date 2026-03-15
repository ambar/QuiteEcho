import AVFoundation
import Foundation

/// Records microphone audio and writes it to a temporary WAV file.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var isRecording = false
    private(set) var level: Float = 0

    /// Start recording.  Throws if the audio engine fails to start.
    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiteecho_\(UUID().uuidString).wav")

        let node = engine.inputNode
        let hwFormat = node.outputFormat(forBus: 0)

        // Write in hardware format; the Python worker resamples to 16 kHz.
        audioFile = try AVAudioFile(forWriting: url, settings: hwFormat.settings)

        node.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)

            // RMS level for the overlay meter
            if let samples = buffer.floatChannelData?[0] {
                var sum: Float = 0
                let count = Int(buffer.frameLength)
                for i in 0..<count { sum += abs(samples[i]) }
                self.level = sum / max(Float(count), 1)
            }
        }

        try engine.start()
        isRecording = true
    }

    /// Stop recording and return the WAV file URL (nil if nothing was captured).
    func stop() -> URL? {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false

        let url = audioFile?.url
        audioFile = nil
        return url
    }
}
