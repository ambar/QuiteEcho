import AppKit
import QuartzCore

private let kPanelH: CGFloat = 36
private let kBarCount = 5
private let kBarWidth: CGFloat = 3
private let kBarGap: CGFloat = 3.5
private let kBarMaxH: CGFloat = 18
private let kBarMinH: CGFloat = 3
private let kIdleH: CGFloat = 5

/// A floating capsule HUD at the bottom of the screen.
final class OverlayPanel {
    private let panel: NSPanel
    private let container: NSView
    private let waveView: WaveBarView
    private let dotView: DotView
    private let label: NSTextField
    private var animTimer: Timer?
    private var dismissTimer: Timer?

    /// Set from outside (AppDelegate timer) to drive wave amplitude.
    var audioLevel: Float = 0

    init() {
        let barsW = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
        let maxPanelW: CGFloat = 200

        let screen = NSScreen.main?.frame ?? .zero
        let x = (screen.width - maxPanelW) / 2
        let y = screen.height * 0.10

        panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: maxPanelW, height: kPanelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating + 1
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0

        // Solid black rounded container
        container = NSView(frame: NSRect(x: 0, y: 0, width: maxPanelW, height: kPanelH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = kPanelH / 2
        container.layer?.masksToBounds = true
        panel.contentView = container

        // Wave bars (centered in panel)
        let barsX = (maxPanelW - barsW) / 2
        let barsY = (kPanelH - kBarMaxH) / 2
        waveView = WaveBarView(frame: NSRect(x: barsX, y: barsY, width: barsW, height: kBarMaxH))
        waveView.isHidden = true
        container.addSubview(waveView)

        // Dot (for non-recording states)
        let dotSize: CGFloat = 7
        dotView = DotView(frame: NSRect(x: 16, y: (kPanelH - dotSize) / 2, width: dotSize, height: dotSize))
        container.addSubview(dotView)

        // Label (vertically centered)
        label = NSTextField(frame: NSRect(x: 30, y: 0, width: maxPanelW - 48, height: kPanelH))
        let cell = VerticallyCenteredTextFieldCell()
        cell.font = .systemFont(ofSize: 12, weight: .medium)
        cell.textColor = .white
        cell.isEditable = false
        cell.isBordered = false
        cell.drawsBackground = false
        cell.isScrollable = false
        cell.wraps = false
        cell.lineBreakMode = .byTruncatingTail
        label.cell = cell
        container.addSubview(label)
    }

    // MARK: - Public

    func showRecording() {
        stopPulse()
        dotView.isHidden = true
        label.isHidden = true
        waveView.isHidden = false

        let barsW = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
        let compactW = barsW + 36
        resizePanel(width: compactW)

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startWaveAnimation()
    }

    func showProcessing() {
        stopWaveAnimation()
        waveView.isHidden = true
        dotView.isHidden = false
        label.isHidden = true
        dotView.color = .white

        let barsW = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
        let compactW = barsW + 36
        resizePanel(width: compactW)
        // Center dot in compact panel
        let dotSize = dotView.frame.size
        dotView.frame.origin.x = (compactW - dotSize.width) / 2

        startPulse()
    }

    func showDone(_ text: String) {
        stopWaveAnimation()
        stopPulse()
        waveView.isHidden = true
        dotView.isHidden = false
        label.isHidden = false
        dotView.color = .systemGreen
        let display = text.count > 28 ? String(text.prefix(28)) + "..." : text
        label.stringValue = display
        resizePanel(width: max(160, min(CGFloat(display.count) * 8 + 52, 300)))
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func showError(_ message: String) {
        stopWaveAnimation()
        stopPulse()
        waveView.isHidden = true
        dotView.isHidden = false
        label.isHidden = false
        dotView.color = .systemRed
        label.stringValue = message
        resizePanel(width: 160)
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        stopWaveAnimation()
        stopPulse()
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel.orderOut(nil)
        panel.alphaValue = 0
    }

    // MARK: - Internals

    private func resizePanel(width: CGFloat) {
        let screen = NSScreen.main?.frame ?? .zero
        var frame = panel.frame
        let cx = screen.midX
        frame.origin.x = cx - width / 2
        frame.size.width = width
        panel.setFrame(frame, display: true)

        container.frame = NSRect(x: 0, y: 0, width: width, height: kPanelH)

        // Re-center wave
        let barsW = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
        waveView.frame.origin.x = (width - barsW) / 2

        // Reposition dot + label
        dotView.frame.origin.x = 16
        label.frame = NSRect(x: 30, y: 0, width: width - 48, height: kPanelH)
    }

    private func startPulse() {
        stopPulse()
        dotView.wantsLayer = true
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.25
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotView.layer?.add(anim, forKey: "pulse")
    }

    private func stopPulse() {
        dotView.layer?.removeAnimation(forKey: "pulse")
        dotView.layer?.opacity = 1.0
    }

    private func startWaveAnimation() {
        stopWaveAnimation()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.waveView.audioLevel = self.audioLevel
            self.waveView.tick()
        }
    }

    private func stopWaveAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - WaveBarView

private final class WaveBarView: NSView {
    private var phases: [Double] = (0..<kBarCount).map { _ in Double.random(in: 0...(.pi * 2)) }
    private var time: Double = 0
    var audioLevel: Float = 0

    func tick() {
        time += 0.07
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Map audio level (typically 0...0.3) to an amplitude multiplier
        let level = Double(min(audioLevel / 0.15, 1.0))  // normalize to 0...1
        let dynamicMax = kIdleH + CGFloat(level) * (kBarMaxH - kIdleH)

        for i in 0..<kBarCount {
            let freq = 1.6 + Double(i) * 0.5
            let norm = (sin(time * freq + phases[i]) + 1) / 2
            let h = kBarMinH + CGFloat(norm) * (dynamicMax - kBarMinH)
            let x = CGFloat(i) * (kBarWidth + kBarGap)
            let y = (bounds.height - h) / 2

            let rect = NSRect(x: x, y: y, width: kBarWidth, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: kBarWidth / 2, yRadius: kBarWidth / 2)

            let alpha = 0.6 + 0.4 * CGFloat(norm)
            NSColor.white.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }
}

// MARK: - VerticallyCenteredTextFieldCell

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        let textH = cellSize(forBounds: rect).height
        let delta = base.height - textH
        if delta > 0 {
            return NSRect(x: base.origin.x, y: base.origin.y + delta / 2,
                          width: base.width, height: textH)
        }
        return base
    }
}

// MARK: - DotView

private final class DotView: NSView {
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
