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

Powered by [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) — all-in-one speech recognition supporting 30 languages and 22 Chinese dialects, with speech, singing, and background music handling.

| Model | Notes |
|---|---|
| Qwen3-ASR-0.6B | Default. Faster inference, lower memory — good accuracy-efficiency trade-off |
| Qwen3-ASR-1.7B | State-of-the-art accuracy among open-source ASR, competitive with commercial APIs |

Models are downloaded on first use.

## Requirements

- macOS 14+, Apple Silicon
- Microphone and Accessibility permissions (prompted on first launch)

## License

MIT
