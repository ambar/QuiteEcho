import AppKit
import Carbon

/// Copy text to the system clipboard and simulate ⌘V into the frontmost app.
enum PasteService {
    static func paste(_ text: String, copyToClipboard: Bool = false) {
        let pb = NSPasteboard.general
        let savedItems = copyToClipboard ? nil : snapshotClipboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()

            if let savedItems {
                // Restore previous clipboard contents after ⌘V has read the pasteboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    restoreClipboard(pb, items: savedItems)
                }
            }
        }
    }

    // MARK: - Clipboard save / restore

    private static func snapshotClipboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.compactMap { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restoreClipboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
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
