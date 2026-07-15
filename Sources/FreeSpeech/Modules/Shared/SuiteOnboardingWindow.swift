import AppKit
import SwiftUI
import FreeSpeechCore

// App-level (suite) first-run setup: welcome, one-shot permissions, a HyperKey
// nudge, then a per-tool enable+hotkey walkthrough. Distinct from Speech's own
// detailed onboarding (OnboardingWindow.swift), which only fires once Speech
// itself is turned on. Shares that window's chrome so the two read as one app.
final class SuiteOnboardingStore: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, permissions, hyperKey, tools, done
    }

    // A permission the suite as a whole may want; none are a hard gate here.
    struct PermissionInfo: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let detail: String
        let recommended: Bool
    }

    let permissions: [PermissionInfo] = [
        PermissionInfo(
            id: "accessibility", name: "Accessibility", symbol: "accessibility",
            detail: "Lets FreeKit use global hotkeys, type dictated text at your cursor, and auto-click — required by most tools.",
            recommended: true),
        PermissionInfo(
            id: "microphone", name: "Microphone", symbol: "mic",
            detail: "On-device dictation: Speech hears your voice locally, nothing leaves your Mac.",
            recommended: false),
        PermissionInfo(
            id: "screen", name: "Screen Recording", symbol: "macwindow.on.rectangle",
            detail: "Dictate what an app is playing, and read on-screen context so names come out right.",
            recommended: false),
        PermissionInfo(
            id: "camera", name: "Camera", symbol: "camera",
            detail: "The Notch's camera mirror — a quick flip-down view of your webcam.",
            recommended: false),
    ]

    // Only the four modules that read a generic per-module hotkey get an inline
    // recorder; the defaults mirror each module's own so the button shows the
    // real current binding. Speech, Stats, etc. are absent on purpose.
    static let hotkeyDefaults: [String: HotkeyPreset] = [
        ModuleCatalog.notebook.id: .custom(keyCode: 45, modifiers: [.control, .option]),
        ModuleCatalog.autoclicker.id: .custom(keyCode: 17, modifiers: [.control, .option]),
        ModuleCatalog.clop.id: .disabled,
        ModuleCatalog.convert.id: .disabled,
    ]

    let registry: ModuleRegistry
    private let settings: Settings
    private let permissionCoach: PermissionCoachController
    private let onFinished: () -> Void
    private var statusTimer: Timer?

    @Published var step: Step = .welcome
    @Published var granted: [String: Bool] = [:]

    init(registry: ModuleRegistry, settings: Settings,
         permissionCoach: PermissionCoachController, onFinished: @escaping () -> Void) {
        self.registry = registry
        self.settings = settings
        self.permissionCoach = permissionCoach
        self.onFinished = onFinished
        refreshPermissions()
    }

    var stepIndex: Int { step.rawValue + 1 }
    var stepCount: Int { Step.allCases.count }
    var canGoBack: Bool { step != .welcome }

    // Every built tool except HyperKey, which gets its own recommend step.
    var toolModules: [ModuleInfo] {
        ModuleCatalog.all.filter { $0.status == .available && $0.id != ModuleCatalog.hyperKey.id }
    }

    func next() {
        guard let nextStep = Step(rawValue: step.rawValue + 1) else { finish(); return }
        leave(step); step = nextStep; enter(nextStep)
    }
    func back() {
        guard let prevStep = Step(rawValue: step.rawValue - 1) else { return }
        leave(step); step = prevStep; enter(prevStep)
    }

    private func enter(_ step: Step) {
        if step == .permissions { startStatusPolling() }
    }
    private func leave(_ step: Step) {
        if step == .permissions { stopStatusPolling() }
    }

    // MARK: Modules

    func isEnabled(_ id: String) -> Bool { registry.isEnabled(id: id) }

    func setEnabled(_ enabled: Bool, _ id: String) {
        registry.setEnabled(enabled, id: id)
        objectWillChange.send()
    }

    func hotkey(_ id: String) -> HotkeyPreset {
        settings.moduleHotkey(id: id, defaultPreset: Self.hotkeyDefaults[id] ?? .disabled)
    }

    // A live tool captured its hotkey token at activate() time, so re-registering
    // it is the contained way to make a changed binding take effect without
    // reaching into each module's private install path.
    func setHotkey(_ preset: HotkeyPreset, _ id: String) {
        settings.setModuleHotkey(preset, id: id)
        if registry.isEnabled(id: id) {
            registry.setEnabled(false, id: id)
            registry.setEnabled(true, id: id)
        }
    }

    // MARK: Permissions

    func request(_ id: String) {
        switch id {
        case "accessibility":
            if !Permissions.accessibilityTrusted(promptIfNeeded: true) {
                Permissions.openAccessibilitySettings()
            }
            refreshPermissions()
        case "microphone":
            Permissions.requestMicrophone { [weak self] granted in
                if !granted, Permissions.microphoneDenied() {
                    self?.permissionCoach.show(.microphone)
                }
                self?.refreshPermissions()
            }
        case "screen":
            if !Permissions.screenRecordingAuthorized(requestIfNeeded: true) {
                Permissions.openScreenRecordingSettings()
            }
            refreshPermissions()
        case "camera":
            Permissions.requestCamera { [weak self] granted in
                if !granted { Permissions.openCameraSettings() }
                self?.refreshPermissions()
            }
        default:
            break
        }
    }

    private func refreshPermissions() {
        granted = [
            "accessibility": Permissions.accessibilityTrusted(promptIfNeeded: false),
            "microphone": Permissions.microphoneAuthorized(),
            "screen": Permissions.screenRecordingAuthorized(requestIfNeeded: false),
            "camera": Permissions.cameraAuthorized(),
        ]
    }
    private func startStatusPolling() {
        stopStatusPolling()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }
    private func stopStatusPolling() { statusTimer?.invalidate(); statusTimer = nil }

    // MARK: Finish

    func finish() {
        stopStatusPolling()
        settings.hasCompletedSuiteOnboarding = true
        Log.info("suite onboarding completed")
        onFinished()
    }
    func skipAll() { finish() }
}

struct SuiteOnboardingView: View {
    @ObservedObject var store: SuiteOnboardingStore
    @ObservedObject var registry: ModuleRegistry
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            ScrollView {
                content
                    .id(store.step)
                    .transition(stepTransition)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(DS.animBase, value: store.step)
            footer
        }
        .frame(width: 520, height: 600)
        .background(AppearanceBackground())
        .onChange(of: store.step) { oldStep, newStep in
            forward = newStep.rawValue >= oldStep.rawValue
        }
    }

    private var stepTransition: AnyTransition {
        let dx: CGFloat = forward ? 14 : -14
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: dx)),
            removal: .opacity.combined(with: .offset(x: -dx)))
    }

    @ViewBuilder private var content: some View {
        switch store.step {
        case .welcome: welcome
        case .permissions: permissions
        case .hyperKey: hyperKey
        case .tools: tools
        case .done: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroTitle("Welcome to FreeKit")
            body("FreeKit is a suite of small menu-bar tools — dictation, notes, file conversion, autoclick, and more. Everything runs on your Mac.")
            body("Every tool starts off. This quick setup grants the permissions the suite can use, then walks you through turning on just the tools you want.")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Grant permissions")
            body("Each tool only uses what it needs. Grant these now, or skip and grant them later when a tool asks. None are required to continue.")
            ForEach(store.permissions) { permission in
                permissionRow(permission)
            }
        }
    }

    private var hyperKey: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Turn Caps Lock into a super key")
            body("HyperKey remaps the Caps Lock key you rarely use into a hyper key (Control-Option-Shift-Command) — one clean modifier for your own global shortcuts, with an optional tap-for-Escape.")
            DSSettingsCard(title: "HyperKey") {
                DSToggleRow(
                    title: "Enable HyperKey",
                    caption: "Recommended. Caps Lock becomes a hyper key you can build shortcuts on.",
                    isOn: Binding(
                        get: { store.isEnabled(ModuleCatalog.hyperKey.id) },
                        set: { store.setEnabled($0, ModuleCatalog.hyperKey.id) }))
                if store.isEnabled(ModuleCatalog.hyperKey.id) {
                    Text("Fine-tune it later — Command, tap-for-Escape, and more — in HyperKey's settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Turn on the tools you want")
            body("Flip on what looks useful — you can change any of this later from the Control Center. Tools with a global hotkey let you set it right here.")
            ForEach(store.toolModules) { module in
                toolCard(module)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroTitle("You're set up")
            body("Your enabled tools are running now. Open FreeKit any time from the Dock to add more, change hotkeys, or tweak settings.")
            body("Turned on Speech? Its own quick guided setup opens next.")
        }
    }

    // MARK: Cards

    private func permissionRow(_ permission: SuiteOnboardingStore.PermissionInfo) -> some View {
        let isGranted = store.granted[permission.id] ?? false
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 18))
                .frame(width: 24)
                .foregroundStyle(isGranted ? Color.dsPaper : Color.dsMuted)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(permission.name)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.dsPaper)
                    if permission.recommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).kerning(1)
                            .foregroundStyle(Color.dsAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Color.dsAccent.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(permission.detail)
                    .font(.system(size: 11)).foregroundStyle(Color.dsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isGranted {
                Text("GRANTED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).kerning(1)
                    .foregroundStyle(Color.dsMuted)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Button("Grant") { store.request(permission.id) }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsInk1, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
            .strokeBorder(permission.recommended && !isGranted ? Color.dsAccent.opacity(0.4) : Color.dsLine,
                          lineWidth: 1))
        .animation(DS.animBase, value: isGranted)
    }

    private func toolCard(_ module: ModuleInfo) -> some View {
        let enabled = registry.isEnabled(id: module.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 18))
                    .frame(width: 24)
                    .foregroundStyle(enabled ? Color.dsPaper : Color.dsMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(module.displayName)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.dsPaper)
                    Text(module.summary)
                        .font(.system(size: 11)).foregroundStyle(Color.dsMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSToggle(isOn: Binding(
                    get: { store.isEnabled(module.id) },
                    set: { store.setEnabled($0, module.id) }))
            }
            if enabled, SuiteOnboardingStore.hotkeyDefaults[module.id] != nil {
                HotkeyRecorderButton(
                    label: "Hotkey",
                    preset: store.hotkey(module.id),
                    onChange: { store.setHotkey($0, module.id) })
                    .id(module.id)
                    .padding(.leading, 36)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsInk1, in: RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous)
            .strokeBorder(enabled ? Color.dsAccent.opacity(0.35) : Color.dsLine, lineWidth: 1))
        .animation(DS.animBase, value: enabled)
    }

    // MARK: Chrome

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FREEKIT SETUP")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(1.2)
                    .foregroundStyle(Color.dsAccent)
                Spacer()
                Text("STEP \(store.stepIndex) / \(store.stepCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(1.2)
                    .foregroundStyle(Color.dsMuted)
                    .dsValueTransition(store.stepIndex)
            }
            HStack(spacing: 6) {
                ForEach(1...store.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= store.stepIndex ? Color.dsPaper : Color.dsLine)
                        .frame(height: 3)
                }
            }
            .animation(DS.animBase, value: store.stepIndex)
        }
        .padding(.horizontal, 28).padding(.top, 22)
    }

    private var footer: some View {
        HStack {
            if store.canGoBack {
                Button("Back") { store.back() }.buttonStyle(GhostButtonStyle())
            }
            Button("Skip setup") { store.skipAll() }.buttonStyle(GhostButtonStyle())
            Spacer()
            Button(action: { store.next() }) {
                Text(store.step == .done ? "Finish" : "Continue")
                    .font(.system(size: 13, weight: .semibold))
                    .dsContentCrossfade(store.step == .done)
                    .foregroundStyle(Color.dsInk0)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Color.dsPaper,
                               in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(Color.dsInk1)
        .overlay(Rectangle().fill(Color.dsLine).frame(height: 1), alignment: .top)
    }

    // MARK: Text helpers

    private func bigTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.dsPaper)
    }
    private func heroTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.dsPaper)
    }
    private func body(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Color.dsMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

final class SuiteOnboardingWindowController {
    private var window: NSWindow?
    private let registry: ModuleRegistry
    private let settings: Settings
    private let permissionCoach: PermissionCoachController
    private let onFinished: () -> Void

    init(registry: ModuleRegistry, settings: Settings,
         permissionCoach: PermissionCoachController, onFinished: @escaping () -> Void) {
        self.registry = registry
        self.settings = settings
        self.permissionCoach = permissionCoach
        self.onFinished = onFinished
    }

    func show() {
        if window == nil {
            let store = SuiteOnboardingStore(
                registry: registry, settings: settings, permissionCoach: permissionCoach,
                onFinished: { [weak self] in self?.finish() })
            let hosting = NSHostingController(
                rootView: SuiteOnboardingView(store: store, registry: registry))
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = DS.ink0
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        if let window { DSMotionAppKit.presentWindow(window) }
        NSApp.activate(ignoringOtherApps: true)
        Log.info("suite onboarding window opened")
    }

    private func finish() {
        close()
        onFinished()
    }

    func close() {
        if let window { DSMotionAppKit.dismissWindow(window, close: true) }
        window = nil
    }
}
