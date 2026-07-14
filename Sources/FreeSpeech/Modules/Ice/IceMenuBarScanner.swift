import AppKit
import FreeSpeechCore

// Polls the menu bar's own window layer for other apps' status items. Bounds
// and owner metadata are public (CGWindowListCopyWindowInfo) — the same read
// PermissionCoach.settingsWindowFrame() already relies on — so no Screen
// Recording permission is needed; only window content capture is gated.
final class IceMenuBarScanner {
    // NSWindow.Level.statusBar's raw CGWindowLevel; menu bar status items live here.
    private static let statusWindowLayer = 25

    private var timer: Timer?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private(set) var entries: [MenuBarAppEntry] = []
    var onChange: (() -> Void)?

    func start() {
        scan()
        let center = NSWorkspace.shared.notificationCenter
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scanAfterDelay() }
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scan() }
        // Coarse fallback: most apps add/remove their status item on demand,
        // not only around launch/quit, so a periodic rescan catches those too.
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver { center.removeObserver(launchObserver) }
        if let terminateObserver { center.removeObserver(terminateObserver) }
        launchObserver = nil
        terminateObserver = nil
    }

    // A freshly launched app's status item can land a beat after the launch
    // notification fires, so the first rescan is delayed rather than immediate.
    private func scanAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.scan() }
    }

    @discardableResult
    func scan() -> [MenuBarAppEntry] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            Log.error("ice: CGWindowListCopyWindowInfo returned nothing")
            entries = []
            onChange?()
            return entries
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var found: [MenuBarAppEntry] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == Self.statusWindowLayer,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  Int32(ownerPID) != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  // Raw CoreGraphics global space (top-left origin): this must
                  // match the coordinate system CGEventPostToPid expects, so it
                  // is deliberately NOT flipped to AppKit's bottom-left space.
                  let cg = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let pid = Int32(ownerPID)
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName
                ?? (info[kCGWindowOwnerName as String] as? String)
                ?? "Unknown (pid \(pid))"
            found.append(MenuBarAppEntry(
                pid: pid, bundleID: app?.bundleIdentifier, displayName: name, frame: cg))
        }
        // Right-to-left matches the menu bar's own visual order (rightmost
        // item = added first / closest to Control Center).
        entries = found.sorted { $0.frame.minX > $1.frame.minX }
        onChange?()
        return entries
    }

    deinit { stop() }
}
