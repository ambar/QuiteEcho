# QuiteEcho

macOS app for offline speech-to-text. Records audio via hotkey, transcribes with Qwen3-ASR, pastes into the active app. SwiftUI window (Home/Models/Settings) + menubar status icon.

## Build & Run

```sh
make build   # swift build + assemble .app bundle (copies uv to Resources/)
make run     # build + open
make dev     # debug build + run directly
make clean   # clean build artifacts
```

Override uv path: `make build UV_BIN=/path/to/uv`

## Architecture

- **Swift** menubar app (Swift Package Manager, no Xcode project)
- **Python** ASR worker (`scripts/asr_worker.py`) via JSON-line protocol over stdin/stdout
- Dependencies (torch, qwen-asr) installed dynamically at first launch via bundled `uv`

### Key components

| File | Role |
|------|------|
| `AppDelegate.swift` | App lifecycle, hotkey binding, recording flow |
| `ASRBridge.swift` | Manages Python subprocess, JSON-line protocol |
| `BootstrapManager.swift` | First-launch setup: creates venv via bundled `uv`, installs torch + qwen-asr |
| `AudioRecorder.swift` | AVAudioEngine → WAV file |
| `HotkeyManager.swift` | 3 backends: Carbon (regular keys), NSEvent flagsChanged (modifier keys), NSEvent systemDefined (media keys) |
| `PasteService.swift` | NSPasteboard + CGEvent ⌘V simulation |
| `Config.swift` | User config, key code maps, modifier helpers |
| `Stats.swift` | Usage stats (UserDefaults), ICU word counting |
| `MainWindow.swift` | SwiftUI: Home (usage stats), Models, Settings (hotkey/mode/permissions) tabs |
| `OverlayPanel.swift` | Floating HUD (NSPanel, solid black capsule) |
| `StatusBar.swift` | Menubar waveform icon and dropdown menu |
| `scripts/asr_worker.py` | Persistent Python process, Qwen3-ASR model |

### Runtime data locations

- **Python venv**: `~/Library/Application Support/QuiteEcho/.venv/`
- **Model cache**: `~/.cache/huggingface/` (HuggingFace default)
- **User config**: `~/.config/quiteecho/config.json`

### Bootstrap flow

App embeds `uv` binary in `Resources/`. On first launch:
1. `BootstrapManager` creates venv via `uv venv --python 3.13`
2. Installs `qwen-asr` and `torch` via `uv pip install`
3. Writes marker file to skip on subsequent launches
4. `ASRBridge` starts `asr_worker.py` with the venv Python

### ASR worker protocol

```
→ {"cmd":"transcribe","audio":"/path.wav","language":null}
← {"text":"transcribed text"}

→ {"cmd":"reload","model":"Qwen/Qwen3-ASR-1.7B"}
← {"status":"loading"}
← {"status":"ready"}
```

### Hotkey system

| Key type | Backend | Detection |
|---|---|---|
| Regular keys (±modifiers) | Carbon `RegisterEventHotKey` | press + release events |
| Modifier-only (Fn, L⌥, R⌘...) | NSEvent flagsChanged monitors | keyCode distinguishes L/R |
| Media/special fn keys | NSEvent systemDefined monitors | subtype 8, NX_KEYTYPE codes |

Config: `hotkeyKeyCode`, `hotkeyModifiers`, `hotkeyIsMediaKey`, `hotkeyMode` (toggle/hold).

Recorder window **unregisters** hotkey while open to prevent accidental triggers.

## Dev notes

- `pyproject.toml` deps are for local dev (`uv run`); the app uses `BootstrapManager` for production
- All UI text in English
- Semantic colors only — no hardcoded colors, must support light/dark mode
- Word counting: `NSString.enumerateSubstrings(options: .byWords)` (ICU, handles CJK)
- Supported models: `Qwen/Qwen3-ASR-0.6B` (default), `Qwen/Qwen3-ASR-1.7B`
