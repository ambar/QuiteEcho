import Foundation
import MLXAudioSTT
import MLXAudioCore
import MLX

/// Loads and runs an ASR model from mlx-audio-swift. Supports all 6 families
/// declared in `AppConfig.modelFamilies` — dispatch happens at load time via
/// `ModelFamily.Kind`. After loading, calls go through the shared
/// `STTGenerationModel` protocol.
final class ASRBridge {
    enum State: Equatable { case idle, downloading(Double), loading, ready, error(String) }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    private var model: (any STTGenerationModel)?
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

        guard let family = AppConfig.modelFamilies.first(where: { $0.hasVariant(modelId) }) else {
            setState(.error("Unknown model: \(modelId)"))
            return
        }
        let kind = family.kind

        Task.detached { [weak self] in
            do {
                let loaded: any STTGenerationModel = try await Self.load(kind: kind, modelId: modelId)
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

    private static func load(
        kind: AppConfig.ModelFamily.Kind,
        modelId: String
    ) async throws -> any STTGenerationModel {
        switch kind {
        case .qwen3ASR:         return try await Qwen3ASRModel.fromPretrained(modelId)
        case .parakeet:         return try await ParakeetModel.fromPretrained(modelId)
        case .voxtralRealtime:  return try await VoxtralRealtimeModel.fromPretrained(modelId)
        case .glmASR:           return try await GLMASRModel.fromPretrained(modelId)
        case .graniteSpeech:    return try await GraniteSpeechModel.fromPretrained(modelId)
        case .cohereTranscribe: return try await CohereTranscribeModel.fromPretrained(modelId)
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
                    // Preserve the model's per-family tuning and override only
                    // the language field — STTGenerateParameters is immutable,
                    // so we rebuild it from defaults.
                    let d = model.defaultGenerationParameters
                    let params = STTGenerateParameters(
                        maxTokens: d.maxTokens,
                        temperature: d.temperature,
                        topP: d.topP,
                        topK: d.topK,
                        verbose: d.verbose,
                        language: lang,
                        chunkDuration: d.chunkDuration,
                        minChunkDuration: d.minChunkDuration
                    )
                    output = model.generate(audio: audioArray, generationParameters: params)
                } else {
                    // Empty → use per-family default. Qwen3-ASR auto-detects
                    // (upstream #110); Parakeet/Voxtral detect from audio;
                    // GLM-ASR ignores language; Cohere defaults to English
                    // (its own defaultGenerationParameters.language = "en").
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
