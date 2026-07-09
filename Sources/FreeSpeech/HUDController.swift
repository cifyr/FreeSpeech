import AppKit

enum HUDState {
    case recording
    case transcribing
    case processing
    case success
    case error(String)
}

// Non-activating floating panel styled after ETok's Greenlight system (red variant):
// dark glass card, hairline border, mono micro label, red waveform. It floats above
// everything, joins all Spaces, and never steals focus from the dictation target.
final class HUDController {
    private let panel: NSPanel
    private let card = NSView()
    private let waveform = WaveformView()
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var dismissTimer: DispatchWorkItem?
    private var dotPulse: CABasicAnimation?

    private static let size = NSSize(width: 280, height: 72)

    var onAutoDismiss: (() -> Void)?

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
        card.layer?.cornerRadius = DS.radiusCard
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = DS.line.cgColor

        waveform.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = DS.accent.cgColor
        dot.layer?.cornerRadius = 3

        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        card.addSubview(waveform)
        card.addSubview(dot)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            waveform.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            waveform.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            waveform.widthAnchor.constraint(equalToConstant: 216),
            waveform.heightAnchor.constraint(equalToConstant: 28),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -7),
            label.centerXAnchor.constraint(equalTo: card.centerXAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
        ])
        panel.contentView = card
    }

    func show(_ state: HUDState) {
        dismissTimer?.cancel()
        dismissTimer = nil

        switch state {
        case .recording:
            waveform.isHidden = false
            waveform.reset()
            setLabel("Listening", color: DS.paper, showDot: true, pulse: true)
        case .transcribing:
            waveform.isHidden = true
            setLabel("Transcribing", color: DS.muted, showDot: true, pulse: true)
        case .processing:
            waveform.isHidden = true
            setLabel("Polishing", color: DS.muted, showDot: true, pulse: true)
        case .success:
            waveform.isHidden = true
            setLabel("Inserted", color: DS.paper, showDot: true, pulse: false)
            scheduleDismiss(after: 0.8)
        case .error(let message):
            waveform.isHidden = true
            setLabel(message, color: DS.accent, showDot: false, pulse: false)
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
        panel.orderOut(nil)
    }

    private func setLabel(_ text: String, color: NSColor, showDot: Bool, pulse: Bool) {
        // Greenlight micro label: mono, uppercase, wide tracking.
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .kern: 1.2,
                .foregroundColor: color,
            ])
        dot.isHidden = !showDot
        dot.layer?.removeAllAnimations()
        if pulse {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.25
            anim.duration = 0.7
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer?.add(anim, forKey: "pulse")
        }
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
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + 120)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

// Scrolling bar meter in the accent red, fed by RMS levels from the audio tap.
final class WaveformView: NSView {
    private var levels: [Float] = []
    private static let barCount = 36

    func push(level: Float) {
        DispatchQueue.main.async {
            self.levels.append(level)
            if self.levels.count > Self.barCount {
                self.levels.removeFirst(self.levels.count - Self.barCount)
            }
            self.needsDisplay = true
        }
    }

    func reset() {
        levels.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth = bounds.width / CGFloat(Self.barCount)
        for i in 0..<Self.barCount {
            let level = i < levels.count ? levels[i] : 0
            // sqrt compresses dynamic range so quiet speech is still visible
            let normalized = min(1.0, CGFloat(level.squareRoot()) * 2.2)
            let h = max(2, normalized * bounds.height)
            let x = CGFloat(i) * barWidth
            (level > 0 ? DS.accent : DS.ink3).setFill()
            let rect = NSRect(
                x: x + 1, y: (bounds.height - h) / 2,
                width: barWidth - 2, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
