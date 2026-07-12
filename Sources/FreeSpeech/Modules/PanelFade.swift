import AppKit

// Shared appear/disappear treatment for the suite's floating panels (drop
// zone, shelf, toasts): quick fades, no motion, so panels never pop in and
// out abruptly.
extension NSPanel {
    func dsFadeIn(duration: TimeInterval = 0.15) {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
    }

    func dsFadeOut(duration: TimeInterval = 0.18) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = 0
        }) { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        }
    }
}
