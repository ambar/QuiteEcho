import Foundation

/// Tracks usage statistics, persisted via UserDefaults.
struct Stats: Codable {
    var totalSeconds: Double = 0
    var wordsDictated: Int = 0
    var sessionsCount: Int = 0
    /// Characters typed (for CJK-aware metrics).
    var charactersDictated: Int = 0

    var avgWPM: Int {
        guard totalSeconds > 10 else { return 0 }
        return Int(Double(wordsDictated) / (totalSeconds / 60.0))
    }

    var formattedTime: String {
        let total = Int(totalSeconds)
        if total < 60  { return "\(total)s" }
        if total < 3600 { return "\(total / 60) min" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// Estimated time saved vs typing.
    /// English: ~40 WPM typing, CJK: ~30 chars/min typing.
    var timeSaved: String {
        guard charactersDictated > 0, totalSeconds > 0 else { return "--" }
        // Estimate typing time based on character count (works for all languages)
        let typingCharsPerMin: Double = 35
        let typingSeconds = Double(charactersDictated) / typingCharsPerMin * 60.0
        let saved = max(0, typingSeconds - totalSeconds)
        let s = Int(saved)
        if s < 60  { return "\(s)s" }
        if s < 3600 { return "\(s / 60) min" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    // MARK: - Persistence

    private static let key = "com.quiteecho.stats"

    static func load() -> Stats {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Stats.self, from: data)
        else { return Stats() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            NSLog("[Stats] Failed to encode stats")
            return
        }
        UserDefaults.standard.set(data, forKey: Stats.key)
    }

    mutating func recordSession(text: String, durationSeconds: Double) {
        sessionsCount += 1
        totalSeconds += durationSeconds
        wordsDictated += Self.countWords(text)
        charactersDictated += text.filter { !$0.isWhitespace && !$0.isNewline }.count
        save()
    }

    /// Count words using ICU word boundary analysis (like JS Intl.Segmenter).
    /// Handles CJK, Latin, mixed text correctly.
    static func countWords(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        let ns = text as NSString
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: .byWords
        ) { _, _, _, _ in count += 1 }
        return max(count, 1)
    }
}
