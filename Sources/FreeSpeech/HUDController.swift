import AppKit
import FreeSpeechCore

enum HUDState {
    case recording(AudioSource)
    case transcribing
    case processing
    case success
    case error(String)
}

// Non-activating floating panel, Greenlight-red: one fixed line that is always
// in motion. The animated waveform IS the HUD while listening; status text swaps
// into the same line for the other states. Never two rows at once.
final class HUDController {
    private let panel: NSPanel
    private let card = NSView()
    private let waveform = WaveformLineView()
    private let sourceTag = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private var dismissTimer: DispatchWorkItem?

    private static let size = NSSize(width: 280, height: 44)

    var onAutoDismiss: (() -> Void)?
    var hudPosition: HUDPosition = .bottomCenter

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        card.frame = NSRect(origin: .zero, size: Self.size)
        card.wantsLayer = true
        card.layer?.backgroundColor = DS.glass.cgColor
        card.layer?.cornerRadius = DS.radiusControl
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = DS.line.cgColor

        waveform.translatesAutoresizingMaskIntoConstraints = false
        sourceTag.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail

        card.addSubview(waveform)
        card.addSubview(sourceTag)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            // The system-audio tag shares the single line with the waveform.
            sourceTag.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            sourceTag.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            waveform.leadingAnchor.constraint(equalTo: sourceTag.trailingAnchor, constant: 8),
            waveform.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            waveform.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        panel.contentView = card
    }

    func show(_ state: HUDState) {
        dismissTimer?.cancel()
        dismissTimer = nil

        switch state {
        case .recording(let source):
            showWaveform(source: source)
        case .transcribing:
            showText("Transcribing", color: DS.muted)
        case .processing:
            showText("Polishing", color: DS.muted)
        case .success:
            showText("Inserted", color: DS.paper)
            scheduleDismiss(after: 0.8)
        case .error(let message):
            showText(message, color: DS.accent)
            scheduleDismiss(after: 3.5)
        }

        position()
        if !panel.isVisible {
            animateIn()
        }
    }

    func updateLevel(_ level: Float) {
        waveform.push(level: level)
    }

    func dismiss() {
        dismissTimer?.cancel()
        dismissTimer = nil
        waveform.stopAnimating()
        panel.orderOut(nil)
    }

    private func showWaveform(source: AudioSource) {
        label.isHidden = true
        waveform.isHidden = false
        if source == .systemAudio {
            sourceTag.isHidden = false
            sourceTag.attributedStringValue = microString("SYSTEM AUDIO", color: DS.accent)
        } else {
            sourceTag.isHidden = true
            sourceTag.attributedStringValue = NSAttributedString(string: "")
        }
        waveform.startAnimating()
    }

    private func showText(_ text: String, color: NSColor) {
        waveform.stopAnimating()
        waveform.isHidden = true
        sourceTag.isHidden = true
        label.isHidden = false
        label.attributedStringValue = microString(text, color: color)
    }

    // Greenlight micro label: mono, uppercase, wide tracking.
    private func microString(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .kern: 1.2,
                .foregroundColor: color,
            ])
    }

    private func animateIn() {
        panel.alphaValue = 0
        let target = panel.frame
        panel.setFrame(target.offsetBy(dx: 0, dy: -8), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.waveform.stopAnimating()
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.onAutoDismiss?()
            })
        }
        dismissTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 24
        let origin: NSPoint
        switch hudPosition {
        case .bottomCenter:
            origin = NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 120)
        case .topCenter:
            origin = NSPoint(x: frame.midX - Self.size.width / 2, y: frame.maxY - Self.size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: frame.minX + margin, y: frame.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: frame.maxX - Self.size.width - margin, y: frame.minY + margin)
        }
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

// The single always-moving line: a gentle traveling idle wave that speech
// amplitude rides on top of, drawn as accent-red bars.
final class WaveformLineView: NSView {
    private static let barCount = 40
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    private var history: [Float] = []
    private var phase: CGFloat = 0
    private var timer: Timer?

    func push(level: Float) {
        DispatchQueue.main.async {
            self.history.append(level)
            if self.history.count > Self.barCount {
                self.history.removeFirst(self.history.count - Self.barCount)
            }
        }
    }

    func startAnimating() {
        history.removeAll()
        guard timer == nil else { return }
        // Timer drives the idle motion so the line breathes even at zero input.
        timer = Timer.scheduledTimer(withTimeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.16
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        history.removeAll()
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth = bounds.width / CGFloat(Self.barCount)
        for i in 0..<Self.barCount {
            // Two out-of-phase sines make the idle motion feel organic, not metronomic.
            let x = CGFloat(i)
            let idle = 0.10 + 0.06 * sin(phase + x * 0.55) * sin(phase * 0.7 + x * 0.23)
            let historyIndex = history.count - Self.barCount + i
            let level = historyIndex >= 0 && historyIndex < history.count ? history[historyIndex] : 0
            let speech = min(1.0, CGFloat(level.squareRoot()) * 2.2)
            let normalized = max(CGFloat(idle), speech)
            let h = max(2, normalized * bounds.height)
            DS.accent.setFill()
            let rect = NSRect(
                x: x * barWidth + 1, y: (bounds.height - h) / 2,
                width: barWidth - 2, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
