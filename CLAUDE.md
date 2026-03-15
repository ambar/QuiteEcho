# QuiteEcho

macOS app for offline speech-to-text. Records audio via hotkey, transcribes with Qwen3-ASR via mlx-audio-swift (native Apple Silicon), pastes into the active app. SwiftUI window (Home/Models/Settings) + menubar status icon.

## Build & Run

```sh
make build   # swift build + assemble .app bundle
make run     # build + open
make dev     # debug build + run directly
make clean   # clean build artifacts
```

## Architecture

- **Swift** menubar app (Swift Package Manager, no Xcode project)
- **Native ASR** via [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — no Python, no venv, runs directly on Apple Silicon
- Models downloaded from HuggingFace hub on first use, cached locally

### Key components

| File | Role |
|------|------|
| `AppDelegate.swift` | App lifecycle, hotkey binding, recording flow |
| `ASRBridge.swift` | Loads Qwen3-ASR model via mlx-audio-swift, runs transcription |
| `AudioRecorder.swift` | AVAudioEngine → WAV file |
| `HotkeyManager.swift` | 3 backends: Carbon (regular keys), NSEvent flagsChanged (modifier keys), NSEvent systemDefined (media keys) |
| `PasteService.swift` | NSPasteboard + CGEvent ⌘V simulation |
| `Config.swift` | User config, key code maps, modifier helpers |
| `Stats.swift` | Usage stats (UserDefaults), ICU word counting |
| `MainWindow.swift` | SwiftUI: Home (usage stats), Models, Settings (hotkey/mode/permissions) tabs |
| `OverlayPanel.swift` | Floating HUD (NSPanel, solid black capsule) |
| `StatusBar.swift` | Menubar waveform icon and dropdown menu |

### Runtime data locations

- **Model cache**: `~/.cache/huggingface/` (HuggingFace default)
- **User config**: `~/.config/quiteecho/config.json`

### ASR flow

On launch, `ASRBridge.start()` loads the model via `Qwen3ASRModel.fromPretrained()` (async, downloads if needed). Transcription uses `model.generate(audio:)` on a background queue. Audio is loaded and resampled to 16kHz via `loadAudioArray()`.

### Hotkey system

| Key type | Backend | Detection |
|---|---|---|
| Regular keys (±modifiers) | Carbon `RegisterEventHotKey` | press + release events |
| Modifier-only (Fn, L⌥, R⌘...) | NSEvent flagsChanged monitors | keyCode distinguishes L/R |
| Media/special fn keys | NSEvent systemDefined monitors | subtype 8, NX_KEYTYPE codes |

Config: `hotkeyKeyCode`, `hotkeyModifiers`, `hotkeyIsMediaKey`, `hotkeyMode` (toggle/hold).

Recorder window **unregisters** hotkey while open to prevent accidental triggers.

## Dev notes

- Requires Swift 6.2 (Xcode 26+), Apple Silicon, macOS 14+
- All UI text in English
- Semantic colors only — no hardcoded colors, must support light/dark mode
- Word counting: `NSString.enumerateSubstrings(options: .byWords)` (ICU, handles CJK)
- Supported models: `mlx-community/Qwen3-ASR-0.6B-8bit` (default), `mlx-community/Qwen3-ASR-1.7B-8bit`, `mlx-community/Qwen3-ASR-1.7B-4bit`
