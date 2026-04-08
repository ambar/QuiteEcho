import AppKit
import Carbon

/// Copy text to the system clipboard and simulate ⌘V into the frontmost app.
enum PasteService {
    static func paste(_ text: String, copyToClipboard: Bool = false) {
        let pb = NSPasteboard.general
        let savedItems = copyToClipboard ? nil : snapshotClipboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let expectedChangeCount = pb.changeCount

        // 50 ms: give the front app time to receive the ⌘V CGEvent
        // 150 ms: give the front app time to actually read the pasteboard after ⌘V
        // Total 200 ms window; increase if paste fails on slow/Electron apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()

            if let savedItems {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // Only restore if nobody else has touched the clipboard
                    guard pb.changeCount == expectedChangeCount else { return }
                    restoreClipboard(pb, items: savedItems)
                }
            }
        }
    }

    // MARK: - Clipboard save / restore

    /// Returns `nil` if the clipboard cannot be fully serialized (e.g. lazy data providers from other apps).
    private static func snapshotClipboard(_ pb: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pb.pasteboardItems else { return [] }
        var copied: [NSPasteboardItem] = []
        for original in items {
            let item = NSPasteboardItem()
            var hasData = false
            for type in original.types {
                if let data = original.data(forType: type) {
                    item.setData(data, forType: type)
                    hasData = true
                }
            }
            if !hasData { return nil }
            copied.append(item)
        }
        return copied
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
