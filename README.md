# The Quiet Echo

A fully offline speech-to-text app for macOS. No cloud, no network requests, no waiting. Your voice hits the local model and comes back as text — instantly.

- **Zero latency**: On-device inference with no round-trips. Press, speak, paste.
- **Zero telemetry**: Nothing leaves your machine. Ever.
- **Minimal UI**: A hotkey and a floating HUD. Stay in flow.

Powered by [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR).

## Usage

Default hotkey: **Fn (hold)** — hold to record, release to transcribe and paste.

| Mode   | Behavior                                       |
|--------|------------------------------------------------|
| Hold   | Hold key to record, release to stop and paste  |
| Toggle | Press to start recording, press again to stop  |

## Models

| Model | Size | Notes |
|---|---|---|
| Qwen3-ASR-0.6B | ~1.8 GB | Default, faster |
| Qwen3-ASR-1.7B | ~4.4 GB | More accurate |

Models are downloaded on first use.

## Requirements

- macOS 14+, Apple Silicon
- Microphone and Accessibility permissions (prompted on first launch)

## License

MIT
