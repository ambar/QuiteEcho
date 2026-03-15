import Foundation
import MLXAudioSTT
import MLXAudioCore
import MLX

/// Manages a native Qwen3-ASR model via mlx-audio-swift.
final class ASRBridge {
    enum State: Equatable { case idle, downloading(Double), loading, ready, error(String) }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    private var model: Qwen3ASRModel?
    private let queue = DispatchQueue(label: "com.quiteecho.asr", qos: .userInitiated)

    // MARK: - Lifecycle

    func start(model modelId: String, useHFMirror: Bool = false) {
        stop()
        setState(.loading)

        if useHFMirror {
            setenv("HF_ENDPOINT", "https://hf-mirror.com", 1)
        } else {
            unsetenv("HF_ENDPOINT")
        }

        Task.detached { [weak self] in
            do {
                let loaded = try await Qwen3ASRModel.fromPretrained(modelId)
                DispatchQueue.main.async {
                    self?.model = loaded
                    self?.setState(.ready)
                }
            } catch {
                let msg = error.localizedDescription
                NSLog("[ASR] Failed to load model: %@", msg)
                DispatchQueue.main.async {
                    self?.setState(.error(msg))
                }
            }
        }
    }

    func stop() {
        model = nil
        setState(.idle)
    }

    // MARK: - Commands

    func transcribe(audioPath: String, language: String?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let model = self.model else {
            completion(.failure(NSError(domain: "ASR", code: -2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])))
            return
        }

        queue.async {
            do {
                let url = URL(fileURLWithPath: audioPath)
                let (_, audioArray) = try loadAudioArray(from: url, sampleRate: 16000)
                let output: STTOutput
                if let lang = language, !lang.isEmpty {
                    output = model.generate(audio: audioArray, language: lang)
                } else {
                    output = model.generate(audio: audioArray)
                }
                DispatchQueue.main.async {
                    completion(.success(output.text))
                }
            } catch {
                NSLog("[ASR] Transcription error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func reload(model modelId: String, useHFMirror: Bool = false) {
        start(model: modelId, useHFMirror: useHFMirror)
    }

    // MARK: - Internal

    private func setState(_ s: State) {
        state = s
        onStateChange?(s)
    }

    deinit { stop() }
}
