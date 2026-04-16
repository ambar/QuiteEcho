import AppKit
import Foundation

struct AppConfig: Codable {
    var model: String = "mlx-community/Qwen3-ASR-0.6B-8bit"
    var hotkeyKeyCode: Int = 0x3F        // Fn / Globe
    var hotkeyModifiers: Int = 0         // no modifiers
    var hotkeyMode: String = "hold"      // "toggle" or "hold"
    var hotkeyIsMediaKey: Bool = false    // true = NX_KEYTYPE (special fn key)
    var language: String = ""            // empty = auto-detect (supported by Qwen3-ASR since mlx-audio-swift #110)

    // Default language list — used by Qwen3-ASR (config.supportLanguages in
    // HF blob). Cohere supports a narrower subset (see ModelFamily.supportedLanguages);
    // Parakeet v3 / Voxtral auto-detect natively; Granite repurposes the
    // field as a translation target; GLM-ASR ignores it.
    static let supportedLanguages: [String] = [
        "Chinese", "English", "Cantonese", "Japanese", "Korean",
        "Arabic", "French", "German", "Spanish", "Portuguese",
        "Russian", "Italian", "Indonesian", "Thai", "Vietnamese",
        "Turkish", "Hindi", "Malay", "Dutch", "Swedish",
        "Danish", "Finnish", "Polish", "Czech", "Filipino",
        "Persian", "Greek", "Romanian", "Hungarian", "Macedonian",
    ]
    var copyToClipboard: Bool = false    // keep transcribed text on clipboard after pasting
    var useHFMirror: Bool = AppConfig.defaultUseHFMirror
    var autoCheckUpdates: Bool = true    // check GitHub releases on launch
    var betaUpdates: Bool = false        // opt-in to prerelease channel
    var modelVariants: [String: String] = [:]  // family name → selected variant (e.g. "Qwen3-ASR-0.6B": "4bit")

    /// Default value for `useHFMirror`, evaluated at first `AppConfig()`
    /// construction. Fresh installs in mainland China go through the mirror
    /// automatically, since `huggingface.co` is typically unreachable from
    /// there. Existing installs keep whatever value they wrote to disk.
    ///
    /// We key off `region`, not the language code — a user whose interface
    /// is English but whose region is CN still benefits from the mirror.
    static let defaultUseHFMirror: Bool = {
        let region = Locale.current.region?.identifier ?? ""
        return ["CN"].contains(region)
    }()

    // MARK: - Persistence

    private static let configDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quiteecho")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let configFile: URL = configDir.appendingPathComponent("config.json")

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configFile),
              var config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }

        // Reset unknown model IDs to default
        if !modelFamilies.contains(where: { $0.hasVariant(config.model) }) {
            config.model = AppConfig().model
            config.save()
        }

        // Normalize language against the active family — older saved configs
        // may have a language the newly selected family doesn't accept.
        if let family = config.modelFamily {
            let normalized = family.normalizedLanguage(config.language)
            if normalized != config.language {
                config.language = normalized
                config.save()
            }
        }

        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            NSLog("[Config] Failed to encode config")
            return
        }
        do {
            try data.write(to: Self.configFile, options: .atomic)
        } catch {
            NSLog("[Config] Failed to write: %@", error.localizedDescription)
        }
    }

    // MARK: - Model families

    struct ModelFamily {
        let name: String              // display name, e.g. "Qwen3-ASR-0.6B"
        let description: String
        let kind: Kind                // which mlx-audio-swift class loads it
        let variants: [Variant]
        let defaultVariant: String    // must match one of variants[].name

        struct Variant: Hashable {
            let name: String          // short label, e.g. "8bit"
            let repoId: String        // full HF repo id
        }

        enum Kind {
            case qwen3ASR
            case parakeet
            case voxtralRealtime
            case glmASR
            case graniteSpeech
            case cohereTranscribe
        }

        /// Whether a meaningful language hint can be passed to this family's
        /// `generate()` and routed into the decoder to pick a recognition
        /// language. Qwen3-ASR accepts an optional hint (with auto-detect
        /// fallback); Cohere *requires* one (defaults to English if omitted
        /// and silently falls back to English for unsupported codes).
        /// GLM-ASR ignores the field; Parakeet v3 / Voxtral auto-detect
        /// natively; Granite repurposes it as a *translation target*, which
        /// would be surprising for a "Speech Language" setting.
        var supportsLanguage: Bool {
            switch kind {
            case .qwen3ASR, .cohereTranscribe: return true
            default: return false
            }
        }

        /// Families that identify the spoken language from the audio itself
        /// without accepting a user-selected hint. UI surfaces this as a
        /// read-only note instead of hiding the language section entirely.
        var autoDetectsLanguage: Bool {
            switch kind {
            case .parakeet, .voxtralRealtime: return true
            default: return false
            }
        }

        /// Whether this family supports "Auto" (no explicit language) in
        /// its picker. Qwen3-ASR auto-detects when language is empty;
        /// Cohere does not — leaving it empty silently defaults to English.
        var supportsAutoLanguage: Bool {
            kind == .qwen3ASR
        }

        /// Language code to fall back to when the current user selection
        /// isn't valid for this family (e.g. switching Qwen3 "Cantonese" →
        /// Cohere, which doesn't support Cantonese).
        var defaultLanguage: String {
            kind == .cohereTranscribe ? "English" : ""
        }

        /// Languages this family can actually recognize. Nil means the
        /// global `AppConfig.supportedLanguages` applies.
        var supportedLanguages: [String] {
            switch kind {
            case .cohereTranscribe:
                // See CohereTranscribeTokenizer.mapLanguageCode — unknown
                // codes silently fall back to English, so we must not
                // offer languages the model can't actually transcribe.
                return [
                    "English", "French", "German", "Spanish", "Italian",
                    "Portuguese", "Dutch", "Polish", "Greek", "Arabic",
                    "Japanese", "Chinese", "Vietnamese", "Korean",
                ]
            default:
                return AppConfig.supportedLanguages
            }
        }

        /// Coerce a user-selected language into one this family accepts.
        /// Returns the input unchanged when valid; otherwise falls back to
        /// `defaultLanguage`. Families without `supportsLanguage` keep the
        /// field untouched — it's inert for them and the user may want it
        /// preserved when they switch back to a family that uses it.
        func normalizedLanguage(_ current: String) -> String {
            guard supportsLanguage else { return current }
            if current.isEmpty { return supportsAutoLanguage ? "" : defaultLanguage }
            return supportedLanguages.contains(current) ? current : defaultLanguage
        }

        /// Map a variant name to its repo ID, falling back to the default.
        func modelId(_ variantName: String) -> String {
            variants.first { $0.name == variantName }?.repoId
                ?? variants.first { $0.name == defaultVariant }?.repoId
                ?? variants[0].repoId
        }

        func hasVariant(_ modelId: String) -> Bool {
            variants.contains { $0.repoId == modelId }
        }

        func variant(of modelId: String) -> String? {
            variants.first { $0.repoId == modelId }?.name
        }
    }

    static let modelFamilies: [ModelFamily] = [
        // MARK: Qwen3-ASR (Alibaba, multilingual incl. Chinese)
        ModelFamily(
            name: "Qwen3-ASR-0.6B",
            description: "Alibaba — multilingual, faster, lower memory",
            kind: .qwen3ASR,
            variants: [
                .init(name: "4bit", repoId: "mlx-community/Qwen3-ASR-0.6B-4bit"),
                .init(name: "6bit", repoId: "mlx-community/Qwen3-ASR-0.6B-6bit"),
                .init(name: "8bit", repoId: "mlx-community/Qwen3-ASR-0.6B-8bit"),
                .init(name: "bf16", repoId: "mlx-community/Qwen3-ASR-0.6B-bf16"),
            ],
            defaultVariant: "8bit"
        ),
        ModelFamily(
            name: "Qwen3-ASR-1.7B",
            description: "Alibaba — multilingual, higher accuracy",
            kind: .qwen3ASR,
            variants: [
                .init(name: "4bit", repoId: "mlx-community/Qwen3-ASR-1.7B-4bit"),
                .init(name: "6bit", repoId: "mlx-community/Qwen3-ASR-1.7B-6bit"),
                .init(name: "8bit", repoId: "mlx-community/Qwen3-ASR-1.7B-8bit"),
                .init(name: "bf16", repoId: "mlx-community/Qwen3-ASR-1.7B-bf16"),
            ],
            defaultVariant: "8bit"
        ),

        // MARK: Parakeet TDT (NVIDIA, English SOTA speed)
        ModelFamily(
            name: "Parakeet-TDT-0.6B",
            description: "NVIDIA — English ASR, very fast",
            kind: .parakeet,
            variants: [
                .init(name: "v3", repoId: "mlx-community/parakeet-tdt-0.6b-v3"),
            ],
            defaultVariant: "v3"
        ),
        ModelFamily(
            name: "Parakeet-TDT-1.1B",
            description: "NVIDIA — English ASR, larger",
            kind: .parakeet,
            variants: [
                .init(name: "tdt", repoId: "mlx-community/parakeet-tdt-1.1b"),
            ],
            defaultVariant: "tdt"
        ),

        // MARK: Voxtral Realtime (Mistral, streaming multilingual)
        ModelFamily(
            name: "Voxtral-Mini-4B-Realtime",
            description: "Mistral — multilingual realtime streaming",
            kind: .voxtralRealtime,
            variants: [
                .init(name: "4bit", repoId: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"),
                .init(name: "6bit", repoId: "mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit"),
                .init(name: "fp16", repoId: "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"),
            ],
            defaultVariant: "4bit"
        ),

        // MARK: GLM-ASR (Zhipu, compact)
        ModelFamily(
            name: "GLM-ASR-Nano",
            description: "Zhipu — compact ASR, smallest download",
            kind: .glmASR,
            variants: [
                .init(name: "4bit", repoId: "mlx-community/GLM-ASR-Nano-2512-4bit"),
            ],
            defaultVariant: "4bit"
        ),

        // MARK: Granite Speech (IBM, ASR + translation)
        ModelFamily(
            name: "Granite-Speech-1B",
            description: "IBM — ASR + speech translation (en/fr/de/es/pt/ja)",
            kind: .graniteSpeech,
            variants: [
                .init(name: "5bit", repoId: "mlx-community/granite-4.0-1b-speech-5bit"),
            ],
            defaultVariant: "5bit"
        ),

        // MARK: Cohere Transcribe (multilingual encoder-decoder, 14 langs)
        ModelFamily(
            name: "Cohere-Transcribe-03-2026",
            description: "Cohere — multilingual (14 langs), English SOTA",
            kind: .cohereTranscribe,
            variants: [
                .init(name: "fp16", repoId: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"),
            ],
            defaultVariant: "fp16"
        ),
    ]

    var modelFamily: ModelFamily? {
        Self.modelFamilies.first { $0.hasVariant(model) }
    }

    var modelVariant: String {
        modelFamily?.variant(of: model) ?? "8bit"
    }

    var modelLabel: String {
        guard let family = modelFamily else { return model }
        return "\(family.name) (\(modelVariant))"
    }

    /// Get the remembered variant for a family, falling back to its default.
    func variant(for family: ModelFamily) -> String {
        modelVariants[family.name] ?? family.defaultVariant
    }

    /// HuggingFace hub cache directory for a given model ID, in the
    /// canonical `models--<org>--<name>` layout. This is populated as a
    /// side effect by any HubClient download (including mlx-audio-swift's
    /// internal call), so it's a stable anchor for "where are the bytes?"
    /// across upstream refactors — don't hard-code mlx-audio-swift's own
    /// subdirectory scheme, which is an implementation detail.
    static func modelCacheDir(_ modelId: String) -> String {
        let dirName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/\(dirName)").path
    }

    var hotkeyDisplayString: String {
        if hotkeyIsMediaKey {
            return nxKeyTypeToString(hotkeyKeyCode)
        }
        var parts: [String] = []
        if hotkeyModifiers & 0x0100 != 0 { parts.append("⌘") }
        if hotkeyModifiers & 0x0200 != 0 { parts.append("⇧") }
        if hotkeyModifiers & 0x0800 != 0 { parts.append("⌥") }
        if hotkeyModifiers & 0x1000 != 0 { parts.append("⌃") }
        parts.append(keyCodeToString(UInt16(hotkeyKeyCode)))
        return parts.joined()
    }
}

/// Virtual key codes for modifier keys.
let kModifierKeyCodes: Set<UInt16> = [
    0x36, // Right Command
    0x37, // Left Command
    0x38, // Left Shift
    0x3A, // Left Option
    0x3B, // Left Control
    0x3C, // Right Shift
    0x3D, // Right Option
    0x3E, // Right Control
    0x3F, // Fn / Globe
]

/// Convert a macOS virtual key code to a display string.
func keyCodeToString(_ keyCode: UInt16) -> String {
    let map: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x24: "↩",
        0x35: "⎋",
        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        // Modifier keys
        0x36: "Right ⌘", 0x37: "Left ⌘",
        0x38: "Left ⇧", 0x3C: "Right ⇧",
        0x3A: "Left ⌥", 0x3D: "Right ⌥",
        0x3B: "Left ⌃", 0x3E: "Right ⌃",
        0x3F: "Fn",
    ]
    return map[keyCode] ?? String(format: "0x%02X", keyCode)
}

/// Map a modifier keyCode to its NSEvent.ModifierFlags.
func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
    switch keyCode {
    case 0x36, 0x37: return .command
    case 0x38, 0x3C: return .shift
    case 0x3A, 0x3D: return .option
    case 0x3B, 0x3E: return .control
    case 0x3F:       return .function
    default:         return nil
    }
}

/// Display name for NX_KEYTYPE codes (media / special function keys).
func nxKeyTypeToString(_ nxKey: Int) -> String {
    switch nxKey {
    case 0:  return "Volume Up"
    case 1:  return "Volume Down"
    case 2:  return "Brightness Up"
    case 3:  return "Brightness Down"
    case 5:  return "Keyboard Brightness Up"
    case 6:  return "Keyboard Brightness Down"
    case 7:  return "Mute"
    case 16: return "Play / Pause"
    case 17: return "Next Track"
    case 18: return "Previous Track"
    case 20: return "Mission Control"
    case 21: return "Launchpad"
    case 23: return "Spotlight"
    case 24: return "DND"
    case 30: return "Dictation"
    default: return "Special Key \(nxKey)"
    }
}

/// Convert a Carbon modifier mask to the corresponding macOS virtual key modifier.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
    var mods = 0
    if flags.contains(.command) { mods |= 0x0100 }   // cmdKey
    if flags.contains(.shift)   { mods |= 0x0200 }   // shiftKey
    if flags.contains(.option)  { mods |= 0x0800 }   // optionKey
    if flags.contains(.control) { mods |= 0x1000 }   // controlKey
    return mods
}
