import AppKit
import Combine
import SwiftUI
import FreeSpeechCore

// Ice: an always-on "boundary" status item plus the scan/move machinery that
// lets its settings pane show/hide other apps' menu bar icons. FreeKit's own
// tools need none of this — their menu-bar visibility already lives in
// ModuleRegistry/Settings — so this module only adds the "other apps" half
// and surfaces both lists in one place.
final class IceModule: NSObject, AppModule, ObservableObject {
    let info = ModuleCatalog.ice

    private let settings: Settings
    private let permissionCoach: PermissionCoachController
    unowned let registry: ModuleRegistry
    let scanner = IceMenuBarScanner()
    private(set) lazy var mover = IceItemMover(scanner: scanner)

    private var anchorItem: NSStatusItem?
    private var active = false
    private var menuBarVisible = false
    private var peekTimer: Timer?
    private var peeking = false
    // Apps whose owning process has no bundle id can't survive a relaunch in
    // Settings, so hiding them is session-only and tracked here instead.
    private var sessionHiddenPIDs: Set<Int32> = []

    @Published private(set) var entries: [MenuBarAppEntry] = []

    private static let expandedLength: CGFloat = 10_000
    private static let peekDuration: TimeInterval = 5

    init(settings: Settings, registry: ModuleRegistry, permissionCoach: PermissionCoachController) {
        self.settings = settings
        self.registry = registry
        self.permissionCoach = permissionCoach
        super.init()
        scanner.onChange = { [weak self] in
            guard let self else { return }
            let entries = self.scanner.entries
            DispatchQueue.main.async { self.entries = entries }
        }
    }

    func activate() {
        active = true
        scanner.start()
        applyMenuBarConfiguration()
    }

    func deactivate() {
        active = false
        scanner.stop()
        peekTimer?.invalidate()
        peekTimer = nil
        peeking = false
        applyMenuBarConfiguration()
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        menuBarVisible = visible
        applyMenuBarConfiguration()
    }

    var settingsPopupSize: NSSize { NSSize(width: 620, height: 680) }

    func makeSettingsPane() -> AnyView {
        AnyView(IceSettingsView(module: self))
    }

    // MARK: - Hidden-state queries used by the settings view

    func requestAccessibility() {
        permissionCoach.show(.accessibility)
    }

    func isHidden(_ entry: MenuBarAppEntry) -> Bool {
        if let bundleID = entry.bundleID { return settings.iceIsHidden(bundleID: bundleID) }
        return sessionHiddenPIDs.contains(entry.pid)
    }

    private var anyHidden: Bool {
        !settings.iceHiddenBundleIDs.isEmpty || !sessionHiddenPIDs.isEmpty
    }

    // MARK: - Anchor item

    private func applyMenuBarConfiguration() {
        let shouldShow = active && menuBarVisible
        guard shouldShow else {
            anchorItem?.isVisible = false
            return
        }
        if anchorItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "chevron.left.circle",
                accessibilityDescription: "Hidden menu bar items")
            item.button?.toolTip = "Ice: click to peek at hidden menu bar icons"
            item.button?.target = self
            item.button?.action = #selector(peekTapped)
            anchorItem = item
        }
        anchorItem?.isVisible = true
        refreshAnchorLength()
    }

    private func refreshAnchorLength() {
        guard let anchorItem, !peeking else { return }
        anchorItem.length = anyHidden ? Self.expandedLength : NSStatusItem.variableLength
    }

    @objc private func peekTapped() {
        guard let anchorItem, anyHidden else { return }
        peekTimer?.invalidate()
        if peeking {
            peeking = false
            refreshAnchorLength()
            return
        }
        peeking = true
        anchorItem.length = NSStatusItem.variableLength
        Log.info("ice: peeking at hidden items")
        peekTimer = Timer.scheduledTimer(withTimeInterval: Self.peekDuration, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.peeking = false
            self.refreshAnchorLength()
            Log.info("ice: peek ended")
        }
    }

    // MARK: - Show/hide other apps

    // Toggling a checkbox drags that app's item(s) across the boundary once,
    // then persists the result; it does not need to run again until the user
    // (or the app itself) moves the icon again.
    func setHidden(_ hidden: Bool, entry: MenuBarAppEntry) {
        guard Permissions.accessibilityTrusted(promptIfNeeded: true) else {
            Log.error("ice: cannot toggle \(entry.displayName), accessibility not granted")
            permissionCoach.show(.accessibility)
            return
        }
        guard let anchorItem else { return }
        // Collapse first: an already-expanded anchor's own frame sits far off
        // the real item cluster, so it's not a usable drag reference until
        // it's back to its normal width.
        let wasExpanded = anchorItem.length == Self.expandedLength
        if wasExpanded { anchorItem.length = NSStatusItem.variableLength }

        // A length change needs a runloop pass before the window frame
        // reflects it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let anchorMinX = anchorItem.button?.window?.frame.minX ?? 0
            self.mover.setHidden(hidden, pid: entry.pid, anchorMinX: anchorMinX) { [weak self] ok in
                guard let self else { return }
                guard ok else {
                    Log.error("ice: failed to \(hidden ? "hide" : "reveal") \(entry.displayName)")
                    self.refreshAnchorLength()
                    return
                }
                if let bundleID = entry.bundleID {
                    self.settings.setIceHidden(hidden, bundleID: bundleID)
                } else if hidden {
                    self.sessionHiddenPIDs.insert(entry.pid)
                } else {
                    self.sessionHiddenPIDs.remove(entry.pid)
                }
                Log.info("ice: \(entry.displayName) \(hidden ? "hidden" : "revealed")")
                self.refreshAnchorLength()
                self.scanner.scan()
            }
        }
    }

    deinit {
        peekTimer?.invalidate()
    }
}
