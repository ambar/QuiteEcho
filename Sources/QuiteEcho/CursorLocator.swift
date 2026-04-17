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

        // Try text cursor bounds first, fall back to focused element frame
        if let rect = textCursorBounds(of: element) {
            return cgRectToScreen(rect)
        }
        if let rect = elementFrame(of: element) {
            return cgRectToScreen(rect)
        }
        return nil
    }

    /// Bounds of the text cursor (caret) via parameterized AX attribute.
    private static func textCursorBounds(of element: AXUIElement) -> CGRect? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let range = rangeValue else {
            return nil
        }

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
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return rect
    }

    /// Frame of the focused UI element (fallback when text cursor bounds unavailable).
    private static func elementFrame(of element: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: pos, size: size)
    }

    /// Convert CG coordinates (origin at top-left of primary screen) to AppKit screen coordinates.
    private static func cgRectToScreen(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flippedY = primaryHeight - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }
}
