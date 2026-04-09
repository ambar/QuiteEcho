import AppKit
import Foundation

struct AppConfig: Codable {
    var model: String = "mlx-community/Qwen3-ASR-0.6B-8bit"
    var hotkeyKeyCode: Int = 0x3F        // Fn / Globe
    var hotkeyModifiers: Int = 0         // no modifiers
    var hotkeyMode: String = "hold"      // "toggle" or "hold"
    var hotkeyIsMediaKey: Bool = false    // true = NX_KEYTYPE (special fn key)
    var language: String = ""            // empty = model default (English); true auto-detect not supported by Qwen3-ASR

    // Hardcoded from Qwen3-ASR model config (config.supportLanguages in HF blob).
    // Ideally read from Qwen3ASRModel.config.supportLanguages at runtime,
    // pending mlx-audio-swift exposing this property.
    static let supportedLanguages: [String] = [
        "Chinese", "English", "Cantonese", "Japanese", "Korean",
        "Arabic", "French", "German", "Spanish", "Portuguese",
        "Russian", "Italian", "Indonesian", "Thai", "Vietnamese",
        "Turkish", "Hindi", "Malay", "Dutch", "Swedish",
        "Danish", "Finnish", "Polish", "Czech", "Filipino",
        "Persian", "Greek", "Romanian", "Hungarian", "Macedonian",
    ]
    var copyToClipboard: Bool = false    // keep transcribed text on clipboard after pasting
    var useHFMirror: Bool = false        // use hf-mirror.com instead of huggingface.co
    var autoCheckUpdates: Bool = true    // check GitHub releases on launch
    var betaUpdates: Bool = false        // opt-in to prerelease channel
    var modelVariants: [String: String] = [:]  // family name → selected variant (e.g. "Qwen3-ASR-0.6B": "4bit")

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
        let name: String           // e.g. "Qwen3-ASR-0.6B"
        let description: String
        let variants: [String]     // e.g. ["4bit", "6bit", "8bit", "bf16"]
        let defaultVariant: String // e.g. "8bit"

        func modelId(_ variant: String) -> String {
            "mlx-community/\(name)-\(variant)"
        }

        func hasVariant(_ modelId: String) -> Bool {
            variants.contains { modelId == self.modelId($0) }
        }

        func variant(of modelId: String) -> String? {
            variants.first { modelId == self.modelId($0) }
        }
    }

    static let modelFamilies: [ModelFamily] = [
        ModelFamily(
            name: "Qwen3-ASR-0.6B",
            description: "Faster inference, lower memory usage",
            variants: ["4bit", "6bit", "8bit", "bf16"],
            defaultVariant: "8bit"
        ),
        ModelFamily(
            name: "Qwen3-ASR-1.7B",
            description: "Higher accuracy, requires more memory",
            variants: ["4bit", "6bit", "8bit", "bf16"],
            defaultVariant: "8bit"
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

    /// HuggingFace hub cache directory for a given model ID.
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
