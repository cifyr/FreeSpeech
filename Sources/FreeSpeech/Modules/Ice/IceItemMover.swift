import AppKit
import FreeSpeechCore

// Drives the actual hide/reveal: simulates the Cmd-drag gesture macOS itself
// already supports for rearranging menu bar icons, targeted at the owning
// process via CGEventPostToPid so it can't land on whatever the real cursor
// happens to be over. This is the same technique the open-source Ice app
// uses to genuinely move another app's item (not a drawn cover) — built here
// on public CoreGraphics APIs (CGEventPostToPid, CGWindowListCopyWindowInfo)
// instead of Ice's private CGS calls.
final class IceItemMover {
    private static let maxAttemptsPerItem = 2
    private static let dragSteps = 6
    private static let stepDelayMicroseconds: UInt32 = 8_000
    private static let settleDelayMicroseconds: UInt32 = 150_000

    private let scanner: IceMenuBarScanner

    init(scanner: IceMenuBarScanner) {
        self.scanner = scanner
    }

    // Moves every status item currently owned by `pid` across the boundary in
    // one pass — most apps own exactly one item, but a few own more, and all
    // of them need to end up on the same side or the app reads as half-hidden.
    func setHidden(
        _ hidden: Bool, pid: Int32, anchorMinX: CGFloat, completion: @escaping (Bool) -> Void
    ) {
        guard Permissions.accessibilityTrusted(promptIfNeeded: true) else {
            Log.error("ice: cannot move items for pid \(pid), accessibility not trusted")
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = self.driveAllItems(hidden: hidden, pid: pid, anchorMinX: anchorMinX)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private func outOfPlace(pid: Int32, hidden: Bool, anchorMinX: CGFloat) -> [MenuBarAppEntry] {
        scanner.scan().filter {
            $0.pid == pid && IceBoundary.isHidden(itemFrame: $0.frame, anchorMinX: anchorMinX) != hidden
        }
    }

    // Re-scans between every item: moving one item can shift the others'
    // positions enough to change their frames.
    private func driveAllItems(hidden: Bool, pid: Int32, anchorMinX: CGFloat) -> Bool {
        var safety = 0
        var overallOK = true
        while safety < 8 {
            safety += 1
            let remaining = outOfPlace(pid: pid, hidden: hidden, anchorMinX: anchorMinX)
            guard let item = remaining.first else { return overallOK }
            let target = IceBoundary.dragTarget(
                anchorMinX: anchorMinX, itemWidth: item.frame.width, hiding: hidden)
            if !dragItem(item, toX: target, pid: pid) { overallOK = false }
        }
        Log.error("ice: gave up moving pid \(pid) after \(safety) items, some may be out of place")
        return false
    }

    private func dragItem(_ item: MenuBarAppEntry, toX targetX: CGFloat, pid: Int32) -> Bool {
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let end = CGPoint(x: targetX, y: item.frame.midY)
        for attempt in 1...Self.maxAttemptsPerItem {
            postDrag(from: start, to: end, pid: pid)
            usleep(Self.settleDelayMicroseconds)
            let stillThere = scanner.scan().contains {
                $0.pid == pid && abs($0.frame.midX - targetX) < max($0.frame.width, item.frame.width)
            }
            if stillThere { return true }
            Log.info("ice: drag attempt \(attempt) for pid \(pid) did not land, retrying")
        }
        return false
    }

    // Cmd+drag: the same gesture a user performs by hand to rearrange menu bar
    // icons, delivered straight to the owning process rather than the shared
    // session so it can't accidentally act on whatever the cursor is over.
    private func postDrag(from start: CGPoint, to end: CGPoint, pid: Int32) {
        post(.leftMouseDown, at: start, pid: pid)
        usleep(Self.stepDelayMicroseconds)

        for step in 1...Self.dragSteps {
            let fraction = CGFloat(step) / CGFloat(Self.dragSteps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y)
            post(.leftMouseDragged, at: point, pid: pid)
            usleep(Self.stepDelayMicroseconds)
        }

        post(.leftMouseUp, at: end, pid: pid)
    }

    private func post(_ type: CGEventType, at point: CGPoint, pid: Int32) {
        guard let event = CGEvent(
            mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left
        ) else { return }
        event.flags = [.maskCommand]
        event.postToPid(pid)
    }
}
