import AppKit

/// Queries the macOS Accessibility API to find the text cursor (caret) position
/// of the frontmost application. Falls back gracefully when unavailable.
enum CursorLocator {
    /// Returns the screen-coordinate rect of the text cursor in the frontmost app,
    /// or `nil` if it cannot be determined.
    static func currentCursorRect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedAppValue: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
              let focusedApp = focusedAppValue else {
            return nil
        }
        let appElement = focusedApp as! AXUIElement

        // Get the focused UI element (text field, text view, etc.)
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedElement = focusedValue else {
            return nil
        }
        let element = focusedElement as! AXUIElement

        // Get the selected text range (cursor position)
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let range = rangeValue else {
            return nil
        }

        // Get the bounds for the selected range (cursor rect)
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        ) == .success, let bounds = boundsValue else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // Accessibility API uses top-left origin (CG coordinates).
        // Convert to NSScreen bottom-left origin coordinates.
        let mainHeight = NSScreen.main?.frame.height ?? 0
        let flippedY = mainHeight - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }
}
