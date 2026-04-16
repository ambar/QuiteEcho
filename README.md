# The Quiet Echo

A fully offline speech-to-text app for macOS — fast, private, and entirely yours.

- **On-device inference** — press, speak, paste. No round-trips, no waiting.
- **Zero telemetry** — nothing leaves your machine. Ever.
- **Minimal UI** — a hotkey and a floating HUD. Stay in flow.

## Usage

Default hotkey: **Fn (hold)** — hold to record, release to transcribe and paste.

| Mode   | Behavior                                       |
|--------|------------------------------------------------|
| Hold   | Hold key to record, release to stop and paste  |
| Toggle | Press to start recording, press again to stop  |

## Models

Six ASR families, switchable in the Models tab:

| Family | Best for |
|---|---|
| [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) (0.6B / 1.7B) | Multilingual + Chinese (default); 30 languages, 22 dialects |
| Parakeet-TDT (0.6B v3 / 1.1B) | English, highest throughput |
| Voxtral-Mini-4B-Realtime | Streaming, low latency |
| GLM-ASR-Nano | Chinese + Cantonese |
| Granite-Speech-1B | English + speech translation |
| Cohere-Transcribe-03-2026 | English SOTA; 14 languages |

Models download from HuggingFace on first use.

## Requirements

- macOS 14+, Apple Silicon
- Microphone and Accessibility permissions (prompted on first launch)

## License

MIT
