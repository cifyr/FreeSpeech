import AppKit

enum HUDState {
    case recording
    case transcribing
    case success
    case error(String)
}

// Non-activating floating panel: visible above everything, joins all Spaces,
// and never steals keyboard focus from the field being dictated into.
final class HUDController {
    private let panel: NSPanel
    private let waveform = WaveformView()
    private let label = NSTextField(labelWithString: "")
    private var dismissTimer: DispatchWorkItem?

    private static let size = NSSize(width: 260, height: 64)

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

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        waveform.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        effect.addSubview(waveform)
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            waveform.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            waveform.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10),
            waveform.widthAnchor.constraint(equalToConstant: 200),
            waveform.heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
        ])
        panel.contentView = effect
    }

    func show(_ state: HUDState) {
        dismissTimer?.cancel()
        dismissTimer = nil

        switch state {
        case .recording:
            waveform.isHidden = false
            waveform.reset()
            label.stringValue = "Listening…"
        case .transcribing:
            waveform.isHidden = true
            label.stringValue = "Transcribing…"
        case .success:
            waveform.isHidden = true
            label.stringValue = "Inserted"
            scheduleDismiss(after: 0.8)
        case .error(let message):
            waveform.isHidden = true
            label.stringValue = message
            scheduleDismiss(after: 3.5)
        }

        position()
        if !panel.isVisible {
            panel.orderFrontRegardless()
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

    var onAutoDismiss: (() -> Void)?

    private func scheduleDismiss(after seconds: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.onAutoDismiss?()
        }
        dismissTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func position() {
        // Bottom-center of the screen with the keyboard focus (approximated by main).
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + 120)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

// Scrolling bar meter fed by RMS levels from the audio tap.
final class WaveformView: NSView {
    private var levels: [Float] = []
    private static let barCount = 34

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
        guard !levels.isEmpty else { return }
        let barWidth = bounds.width / CGFloat(Self.barCount)
        NSColor.systemRed.setFill()
        for (i, level) in levels.enumerated() {
            // sqrt compresses dynamic range so quiet speech is still visible
            let normalized = min(1.0, CGFloat(level.squareRoot()) * 2.2)
            let h = max(2, normalized * bounds.height)
            let x = CGFloat(i) * barWidth
            let rect = NSRect(
                x: x + 1, y: (bounds.height - h) / 2,
                width: barWidth - 2, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}
