import AppKit
import QuartzCore

private let kPanelH: CGFloat = 30
private let kPanelW: CGFloat = 90
private let kBarCount = 5
private let kBarWidth: CGFloat = 3.5
private let kBarGap: CGFloat = 4
private let kBarMaxH: CGFloat = 22
private let kBarMinH: CGFloat = 4
private let kIdleH: CGFloat = 6

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

        let screen = NSScreen.main?.frame ?? .zero
        let x = (screen.width - kPanelW) / 2
        let y = screen.height * 0.10

        panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: kPanelW, height: kPanelH),
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
        container = NSView(frame: NSRect(x: 0, y: 0, width: kPanelW, height: kPanelH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        container.layer?.cornerRadius = kPanelH / 2
        container.layer?.masksToBounds = true
        panel.contentView = container

        // Wave bars (centered in panel)
        let barsX = (kPanelW - barsW) / 2
        let barsY = (kPanelH - kBarMaxH) / 2
        waveView = WaveBarView(frame: NSRect(x: barsX, y: barsY, width: barsW, height: kBarMaxH))
        waveView.isHidden = true
        container.addSubview(waveView)

        // Dot (for non-recording states)
        let dotSize: CGFloat = 7
        dotView = DotView(frame: NSRect(x: 16, y: (kPanelH - dotSize) / 2, width: dotSize, height: dotSize))
        container.addSubview(dotView)

        // Label (centered both vertically and horizontally)
        label = NSTextField(frame: NSRect(x: 0, y: 0, width: kPanelW, height: kPanelH))
        let cell = VerticallyCenteredTextFieldCell()
        cell.font = .systemFont(ofSize: 12, weight: .medium)
        cell.textColor = .white
        cell.alignment = .center
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
        dismissTimer?.invalidate()
        dismissTimer = nil
        stopPulse()
        dotView.isHidden = true
        label.isHidden = true
        waveView.isHidden = false

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startWaveAnimation()
    }

    func showProcessing() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        stopWaveAnimation()
        waveView.isHidden = true
        dotView.isHidden = false
        label.isHidden = true
        dotView.color = .white
        // Center dot in panel
        let dotSize = dotView.frame.size
        dotView.frame.origin.x = (kPanelW - dotSize.width) / 2

        startPulse()
    }

    func showDone(_ text: String) {
        stopWaveAnimation()
        stopPulse()
        waveView.isHidden = true
        dotView.isHidden = true
        label.isHidden = false
        let display = text.count > 28 ? String(text.prefix(28)) + "..." : text
        label.stringValue = display
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func showError(_ message: String) {
        stopWaveAnimation()
        stopPulse()
        waveView.isHidden = true
        dotView.isHidden = true
        label.isHidden = false
        label.stringValue = message
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
