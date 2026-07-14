import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import SwiftUI
import FreeSpeechCore

// Amphetamine: keep the Mac awake on demand. Session policy (durations,
// vectors, countdown text) lives in Core's AmphetaminePlan; this layer holds
// the actual IOPMAssertions. The assertions belong to this module object, not
// to any window, so a session survives every FreeKit window closing — it ends
// only on timer expiry, an explicit stop, or the app quitting.
//
// Lid-closed keep-awake: an IOPMAssertion only vetoes *idle* sleep, so closing
// the lid still forces sleep no matter what is asserted. The one lever that
// actually works with no external display is the system-wide `SleepDisabled`
// setting (`pmset -a disablesleep 1`), which requires admin privileges — we
// run it via `do shell script … with administrator privileges` (same
// NSAppleScript pattern Convert/Clop already use for Finder automation). This
// is opt-in per session (`keepAwakeWithLidClosed`), never the default, because
// it disables ALL sleep, not just clamshell sleep: left on with the lid closed
// in a bag it can overheat and drain the battery for hours, which is why we
// also shorten `displaysleep` for the duration (so the panel powers off even
// though the system won't sleep) and why AmphetaminePlan's battery floor
// (`shouldEndForBattery`, default 20%) ends the session automatically off AC.
final class AmphetamineModule: NSObject, AppModule {
    let info = ModuleCatalog.amphetamine

    private let settings: Settings
    private var statusItem: NSStatusItem?
    private let paneModel = AmphetaminePaneModel()

    private(set) var activePlan: AmphetaminePlan?
    private var sessionStart: Date?
    private var systemAssertion = IOPMAssertionID(0)
    private var displayAssertion = IOPMAssertionID(0)
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false
    private var tickTimer: Timer?

    // Set only while this session holds `SleepDisabled` down; drives endSession's
    // cleanup and the crash-recovery check in activate().
    private var clamshellOverrideActive = false
    private var originalDisplaySleepMinutes: Int?
    private var lastBatteryCheck = Date.distantPast

    // Raw assertion-type strings, not the kIOPMAssertionType* macros: C
    // #defines of CFSTR don't import into Swift.
    private static let preventIdleSystemSleep = "PreventUserIdleSystemSleep"
    private static let preventIdleDisplaySleep = "PreventUserIdleDisplaySleep"

    enum Key {
        static let keepDisplayAwake = "keepDisplayAwake"
        static let keepAwakeWithLidClosed = "keepAwakeWithLidClosed"
        // Persisted the instant we successfully set SleepDisabled, cleared the
        // instant we successfully unset it — so a crash mid-session leaves a
        // trail activate() can find and clean up, instead of a Mac stuck with
        // sleep disabled indefinitely.
        static let clamshellOverridePending = "clamshellOverridePending"
        // The displaysleep minutes value from before we shortened it to 1, so
        // a crash-recovery pass can restore the user's actual preference
        // instead of guessing.
        static let savedDisplaySleepMinutes = "savedDisplaySleepMinutes"
    }

    init(settings: Settings) {
        self.settings = settings
        super.init()
        paneModel.module = self
    }

    var keepDisplayAwake: Bool {
        get { settings.moduleBool(id: info.id, key: Key.keepDisplayAwake) ?? true }
        set { settings.setModuleBool(newValue, id: info.id, key: Key.keepDisplayAwake) }
    }

    var keepAwakeWithLidClosed: Bool {
        get { settings.moduleBool(id: info.id, key: Key.keepAwakeWithLidClosed) ?? false }
        set { settings.setModuleBool(newValue, id: info.id, key: Key.keepAwakeWithLidClosed) }
    }

    private var clamshellOverridePending: Bool {
        get { settings.moduleBool(id: info.id, key: Key.clamshellOverridePending) ?? false }
        set { settings.setModuleBool(newValue, id: info.id, key: Key.clamshellOverridePending) }
    }

    private var savedDisplaySleepMinutes: Int? {
        get { settings.moduleInt(id: info.id, key: Key.savedDisplaySleepMinutes) }
        set { settings.setModuleInt(newValue, id: info.id, key: Key.savedDisplaySleepMinutes) }
    }

    var isSessionActive: Bool { activePlan != nil }

    var sessionElapsed: TimeInterval {
        sessionStart.map { Date().timeIntervalSince($0) } ?? 0
    }

    var sessionRemaining: TimeInterval? {
        activePlan?.remaining(elapsed: sessionElapsed)
    }

    func activate() {
        // If FreeKit crashed or was force-quit mid-session with the clamshell
        // override on, SleepDisabled can be stuck at 1 with nothing to clear
        // it — check for that every launch rather than only at endSession.
        guard clamshellOverridePending, !clamshellOverrideActive else { return }
        Log.error("amphetamine: found a pending clamshell override from a previous run, clearing it")
        let restoreMinutes = savedDisplaySleepMinutes ?? 10
        if runPrivileged("pmset -a disablesleep 0; pmset -a displaysleep \(restoreMinutes)") {
            clamshellOverridePending = false
            savedDisplaySleepMinutes = nil
        } else {
            Log.error("amphetamine: failed to clear stale SleepDisabled=1 — check `pmset -g` manually")
        }
    }

    func deactivate() {
        endSession(reason: "module disabled")
        statusItem?.isVisible = false
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.target = self
                    button.action = #selector(statusItemClicked)
                    // Right-click is the quick Stay Awake toggle; left-click
                    // opens the tier menu — so the click must reach us instead
                    // of a statically attached NSMenu.
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                }
                statusItem = item
                updateStatusIcon()
            }
            statusItem?.isVisible = true
        } else {
            statusItem?.isVisible = false
        }
    }

    var settingsPopupSize: NSSize { NSSize(width: 600, height: 620) }

    func makeSettingsPane() -> AnyView {
        paneModel.module = self
        return AnyView(AmphetamineSettingsPane(model: paneModel))
    }

    // MARK: - Session lifecycle

    func startSession(duration: AmphetaminePlan.Duration) {
        endSession(reason: "replaced by new session")
        let plan = AmphetaminePlan(
            duration: duration,
            keepDisplayAwake: keepDisplayAwake,
            keepAwakeWithLidClosed: keepAwakeWithLidClosed)
        let vectors = plan.vectors()
        let reason = "FreeKit Amphetamine session (\(duration.displayName))"

        if vectors.clamshellSleep {
            guard enableClamshellOverride() else {
                Log.error("amphetamine: session not started, clamshell override failed or was declined")
                return
            }
        }
        guard createAssertion(
            type: Self.preventIdleSystemSleep, reason: reason, into: &systemAssertion) else {
            Log.error("amphetamine: session not started, system assertion failed")
            if vectors.clamshellSleep { disableClamshellOverride() }
            return
        }
        hasSystemAssertion = true
        if vectors.displayIdleSleep {
            hasDisplayAssertion = createAssertion(
                type: Self.preventIdleDisplaySleep, reason: reason, into: &displayAssertion)
        }
        activePlan = plan
        sessionStart = Date()
        Log.info("amphetamine: session started duration=\(duration.displayName) " +
                  "display=\(vectors.displayIdleSleep) lidClosed=\(vectors.clamshellSleep)")
        // Ticking drives both the menu-bar countdown and timer expiry;
        // indefinite sessions still tick so the settings pane's elapsed
        // readout stays live.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        updateStatusIcon()
        paneModel.objectWillChange.send()
    }

    func endSession(reason: String) {
        guard isSessionActive || hasSystemAssertion || hasDisplayAssertion || clamshellOverrideActive
        else { return }
        if hasSystemAssertion {
            IOPMAssertionRelease(systemAssertion)
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            IOPMAssertionRelease(displayAssertion)
            hasDisplayAssertion = false
        }
        if clamshellOverrideActive {
            disableClamshellOverride()
        }
        tickTimer?.invalidate()
        tickTimer = nil
        activePlan = nil
        sessionStart = nil
        Log.info("amphetamine: session ended (\(reason))")
        updateStatusIcon()
        paneModel.objectWillChange.send()
    }

    // MARK: - Clamshell override (SleepDisabled)

    // True once a session has set SleepDisabled=1 but a crash/force-quit
    // left it stuck — the settings pane offers an immediate retry for this
    // instead of making the user wait for the next launch's activate() check.
    var hasStaleClamshellOverride: Bool { clamshellOverridePending && !clamshellOverrideActive }

    func retryClamshellCleanup() {
        let restoreMinutes = savedDisplaySleepMinutes ?? 10
        if runPrivileged("pmset -a disablesleep 0; pmset -a displaysleep \(restoreMinutes)") {
            clamshellOverridePending = false
            savedDisplaySleepMinutes = nil
            paneModel.objectWillChange.send()
        } else {
            Log.error("amphetamine: retry clamshell cleanup failed — SleepDisabled may still be 1")
        }
    }

    private func enableClamshellOverride() -> Bool {
        let displaySleep = currentDisplaySleepMinutes() ?? 10
        // One prompt for both: disabling all sleep is the actual override;
        // shortening displaysleep keeps the panel from staying lit (and hot)
        // under the closed lid even though the system itself won't sleep.
        guard runPrivileged("pmset -a disablesleep 1; pmset -a displaysleep 1") else { return false }
        savedDisplaySleepMinutes = displaySleep
        clamshellOverridePending = true
        clamshellOverrideActive = true
        Log.info("amphetamine: clamshell override enabled, restoring displaysleep=\(displaySleep)m on end")
        return true
    }

    private func disableClamshellOverride() {
        let restoreMinutes = savedDisplaySleepMinutes ?? 10
        if runPrivileged("pmset -a disablesleep 0; pmset -a displaysleep \(restoreMinutes)") {
            clamshellOverridePending = false
            savedDisplaySleepMinutes = nil
        } else {
            Log.error("amphetamine: failed to disable clamshell override — SleepDisabled may still " +
                      "be 1; the settings pane offers a retry, or run `sudo pmset -a disablesleep 0`")
        }
        clamshellOverrideActive = false
    }

    private func runPrivileged(_ command: String) -> Bool {
        guard let script = NSAppleScript(
            source: "do shell script \"\(command)\" with administrator privileges") else { return false }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.error("amphetamine: privileged command failed: \(command) error=\(errorInfo)")
            return false
        }
        return true
    }

    // Unprivileged: `pmset -g` needs no elevation to read.
    private func currentDisplaySleepMinutes() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("amphetamine: pmset -g failed to launch: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            if parts.first == "displaysleep", parts.count > 1, let minutes = Int(parts[1]) {
                return minutes
            }
        }
        return nil
    }

    private static func readBatteryState() -> (percent: Int?, onACPower: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (nil, true) }
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any] else { continue }
            let current = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let capacity = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let percent = capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : 0
            let onAC = (info[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            return (percent, onAC)
        }
        return (nil, true)
    }

    func toggleStayAwake() {
        if isSessionActive {
            endSession(reason: "stay-awake toggled off")
        } else {
            startSession(duration: .indefinite)
        }
    }

    private func tick() {
        guard let plan = activePlan else { return }
        if plan.isExpired(elapsed: sessionElapsed) {
            endSession(reason: "timer elapsed")
            return
        }
        // Only the clamshell-override path needs the battery floor — the
        // other two vectors just veto idle sleep, so the Mac still sleeps
        // normally on low battery even off AC. Checked every 5s, not every
        // tick, to avoid hammering IOPSCopyPowerSourcesInfo.
        if plan.requiresRootPrivilege, Date().timeIntervalSince(lastBatteryCheck) >= 5 {
            lastBatteryCheck = Date()
            let (percent, onACPower) = Self.readBatteryState()
            if let percent, plan.shouldEndForBattery(percent: percent, onACPower: onACPower) {
                Log.error("amphetamine: ending clamshell-override session, battery at \(percent)% off AC")
                endSession(reason: "battery floor reached")
                return
            }
        }
        updateStatusIcon()
        paneModel.objectWillChange.send()
    }

    private func createAssertion(type: String, reason: String,
                                 into id: inout IOPMAssertionID) -> Bool {
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString, &id)
        guard result == kIOReturnSuccess else {
            Log.error("amphetamine: IOPMAssertionCreateWithName(\(type)) failed: IOReturn \(result)")
            return false
        }
        return true
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            toggleStayAwake()
        } else {
            showMenu()
        }
    }

    // Attach the menu only for the duration of this click: a permanently
    // attached menu would swallow the right-click toggle.
    private func showMenu() {
        guard let statusItem else { return }
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let statusTitle: String
        if let plan = activePlan {
            statusTitle = plan.duration.seconds == nil
                ? "Awake until you stop it"
                : "Awake — \(AmphetaminePlan.countdownText(remaining: sessionRemaining)) left"
        } else {
            statusTitle = "Sleeping normally"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        for duration in AmphetaminePlan.Duration.presets {
            let title = duration.seconds == nil
                ? "Stay Awake Until Stopped"
                : "Keep awake \(duration.displayName)"
            let item = NSMenuItem(
                title: title,
                action: #selector(menuStartSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = durationToken(duration)
            menu.addItem(item)
        }
        if isSessionActive {
            menu.addItem(.separator())
            let stop = NSMenuItem(
                title: "End Session", action: #selector(menuEndSession), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(
            title: "Right-click toggles Stay Awake", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        let lidNote = NSMenuItem(
            title: keepAwakeWithLidClosed
                ? "Keeps running with the lid closed (Settings to turn off)"
                : "Lid-close sleep not held off (enable in Settings)",
            action: nil, keyEquivalent: "")
        lidNote.isEnabled = false
        menu.addItem(lidNote)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Amphetamine Settings\u{2026}", action: #selector(menuOpenSettings),
            keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    // Durations round-trip through the menu as "minutes count or 0 for
    // indefinite" so representedObject stays a plain NSNumber.
    private func durationToken(_ duration: AmphetaminePlan.Duration) -> NSNumber {
        switch duration {
        case .minutes(let m): return NSNumber(value: m)
        case .indefinite: return NSNumber(value: 0)
        }
    }

    private func duration(fromToken token: NSNumber) -> AmphetaminePlan.Duration {
        token.intValue > 0 ? .minutes(token.intValue) : .indefinite
    }

    @objc private func menuStartSession(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? NSNumber else { return }
        startSession(duration: duration(fromToken: token))
    }

    @objc private func menuEndSession() {
        endSession(reason: "menu stop")
    }

    @objc private func menuOpenSettings() {
        openSettings()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(
            systemSymbolName: info.symbolName,
            accessibilityDescription: isSessionActive ? "Amphetamine awake" : "Amphetamine idle")
        // Without isTemplate, contentTintColor is ignored and the glyph draws in its raw
        // (near-black) fill — invisible against the menu bar's dark background.
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = isSessionActive ? DS.muted : nil
        let title: String
        if let plan = activePlan {
            title = " " + AmphetaminePlan.countdownText(
                remaining: plan.duration.seconds == nil ? nil : sessionRemaining)
        } else {
            title = ""
        }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        button.toolTip = isSessionActive
            ? "Amphetamine: keeping the Mac awake (right-click to stop)"
            : "Amphetamine: right-click to stay awake, click for timers"
    }
}

// MARK: - Settings pane

final class AmphetaminePaneModel: ObservableObject {
    weak var module: AmphetamineModule?
}

private struct AmphetamineSettingsPane: View {
    @ObservedObject var model: AmphetaminePaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSettingsCard(title: "Current session") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(model.module?.isSessionActive == true
                                             ? Color.dsAccent : Color.dsPaper)
                            .dsContentCrossfade(statusTitle)
                        Text(statusDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsFaint)
                            .dsContentCrossfade(statusDetail)
                    }
                    Spacer()
                    if model.module?.isSessionActive == true {
                        Button("End Session") { model.module?.endSession(reason: "settings stop") }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
            }

            DSSettingsCard(title: "Keep awake") {
                HStack(spacing: 8) {
                    ForEach(Array(AmphetaminePlan.Duration.presets.enumerated()), id: \.offset) { _, duration in
                        DSChip(title: duration.displayName, selected: false) {
                            model.module?.startSession(duration: duration)
                        }
                        .fixedSize()
                    }
                }
                Text("Timers end the session on their own; \u{201C}Until I stop\u{201D} holds until you end it here or right-click the menu bar icon.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DSSettingsCard(title: "Options") {
                DSToggleRow(
                    title: "Keep the display awake too",
                    caption: "Off keeps only the system awake: the screen may still dim and sleep.",
                    isOn: Binding(
                        get: { model.module?.keepDisplayAwake ?? true },
                        set: { model.module?.keepDisplayAwake = $0 }))
                DSToggleRow(
                    title: "Keep awake with the lid closed",
                    caption: "Disables ALL system sleep (not just clamshell) via `pmset` — needs your admin password once per session. Can drain the battery and warm up the Mac in a bag: only use it on power, and the session auto-ends at 20% battery off AC.",
                    isOn: Binding(
                        get: { model.module?.keepAwakeWithLidClosed ?? false },
                        set: { model.module?.keepAwakeWithLidClosed = $0 }))
                Text("Applies to sessions started after the change.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
            }

            if model.module?.hasStaleClamshellOverride == true {
                DSSettingsCard(title: "Needs attention") {
                    Text("A previous session's sleep-disable didn't clear (likely a crash or force-quit). The Mac may still have all sleep disabled.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsAccent)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry Clearing It") { model.module?.retryClamshellCleanup() }
                        .buttonStyle(GhostButtonStyle())
                }
            }

            DSSettingsCard(title: "Limits") {
                Text("Closing the lid with no external display normally forces sleep — no app-level assertion can veto it. \u{201C}Keep awake with the lid closed\u{201D} above works around that via the system-wide SleepDisabled setting, at the battery/heat cost noted there. Sessions survive FreeKit's windows closing, but not quitting FreeKit.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusTitle: String {
        guard let module = model.module, module.isSessionActive else { return "Sleeping normally" }
        guard let remaining = module.sessionRemaining else { return "Awake until you stop it" }
        return "Awake — \(AmphetaminePlan.countdownText(remaining: remaining)) left"
    }

    private var statusDetail: String {
        guard let module = model.module, module.isSessionActive else {
            return "Pick a timer or right-click the menu bar icon to stay awake."
        }
        return module.keepDisplayAwake
            ? "System and display sleep are both held off."
            : "System sleep is held off; the display may still sleep."
    }
}
