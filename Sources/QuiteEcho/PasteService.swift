import AppKit
import Carbon

/// Copy text to the system clipboard and simulate ⌘V into the frontmost app.
enum PasteService {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    /// Prompt the user for Accessibility permission (call once at launch).
    static func ensureAccessibility() {
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)

        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else {
            NSLog("[Paste] Failed to create CGEvent")
            return
        }

        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
