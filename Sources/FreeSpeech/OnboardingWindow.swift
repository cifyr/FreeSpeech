import AppKit
import SwiftUI
import FreeSpeechCore

// First-run guided setup: welcome, permissions, hotkey, live practice, keywords, done.
// The practice step drives the real dictation pipeline — AppDelegate routes the transcript
// back here (via onPracticeTranscript) instead of inserting it — so the user learns the
// actual hotkey. Nothing is "trained"; it just teaches the flow.
final class OnboardingStore: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, permissions, hotkey, practice, keywords, done
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .hotkey: return "Your hotkey"
            case .practice: return "Try it out"
            case .keywords: return "Your words"
            case .done: return "All set"
            }
        }
    }

    private let settings: FreeSpeechCore.Settings
    private let deps: OnboardingDeps
    private var statusTimer: Timer?

    @Published var step: Step = .welcome
    @Published var micGranted = false
    @Published var accessibilityGranted = false
    @Published var hotkey: HotkeyPreset
    @Published var vocabularyHint: String
    @Published var practiceRound = 0
    @Published var practiceHeard: String?
    @Published var practiceActive = false

    static let practicePrompts = [
        "The quick brown fox jumps over the lazy dog.",
        "Let's meet at three on Friday to review the plan.",
        "My specialty is to use Claude Code on projects.",
    ]

    init(settings: FreeSpeechCore.Settings, deps: OnboardingDeps) {
        self.settings = settings
        self.deps = deps
        self.hotkey = settings.hotkey
        self.vocabularyHint = settings.vocabularyHint
        refreshPermissions()
    }

    var stepIndex: Int { step.rawValue + 1 }
    var stepCount: Int { Step.allCases.count }
    var canGoBack: Bool { step != .welcome }
    var permissionsSatisfied: Bool { micGranted && accessibilityGranted }

    func next() {
        guard let nextStep = Step(rawValue: step.rawValue + 1) else { finish(); return }
        leave(step)
        step = nextStep
        enter(nextStep)
    }

    func back() {
        guard let prevStep = Step(rawValue: step.rawValue - 1) else { return }
        leave(step)
        step = prevStep
        enter(prevStep)
    }

    private func enter(_ step: Step) {
        switch step {
        case .permissions: startStatusPolling()
        case .practice: beginPractice()
        default: break
        }
    }

    private func leave(_ step: Step) {
        switch step {
        case .permissions: stopStatusPolling()
        case .practice: endPractice()
        default: break
        }
    }

    // MARK: Permissions

    func requestMic() { deps.requestMicrophone { [weak self] _ in self?.refreshPermissions() } }
    func requestAccessibility() {
        _ = deps.requestAccessibility()
        refreshPermissions()
    }

    private func refreshPermissions() {
        micGranted = deps.microphoneAuthorized()
        let ax = deps.accessibilityTrusted()
        if ax && !accessibilityGranted { deps.installHotkey() }  // enable practice once trusted
        accessibilityGranted = ax
    }

    private func startStatusPolling() {
        stopStatusPolling()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }
    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // MARK: Hotkey

    func chooseHotkey(_ preset: HotkeyPreset) {
        hotkey = preset
        settings.hotkey = preset
        deps.installHotkey()
    }

    // MARK: Practice

    private func beginPractice() {
        practiceRound = 0
        practiceHeard = nil
        practiceActive = true
        deps.beginPractice { [weak self] transcript in
            DispatchQueue.main.async {
                guard let self else { return }
                self.practiceHeard = transcript ?? "(didn't catch that — try again)"
                self.practiceRound += 1
            }
        }
    }

    private func endPractice() {
        practiceActive = false
        deps.endPractice()
    }

    func nextPrompt() {
        practiceHeard = nil
        if practiceRound >= Self.practicePrompts.count { next() }
    }

    var currentPrompt: String {
        Self.practicePrompts[min(practiceRound, Self.practicePrompts.count - 1)]
    }

    // MARK: Keywords / finish

    func saveKeywords() { settings.vocabularyHint = vocabularyHint }

    func finish() {
        saveKeywords()
        stopStatusPolling()
        endPractice()
        settings.hasCompletedOnboarding = true
        Log.info("onboarding completed")
        deps.onFinished()
    }

    func skipAll() { finish() }
}

// The app-side capabilities onboarding needs, injected so the store stays testable/decoupled.
struct OnboardingDeps {
    var microphoneAuthorized: () -> Bool
    var requestMicrophone: (@escaping (Bool) -> Void) -> Void
    var accessibilityTrusted: () -> Bool
    var requestAccessibility: () -> Bool
    var installHotkey: () -> Void
    var beginPractice: (@escaping (String?) -> Void) -> Void
    var endPractice: () -> Void
    var onFinished: () -> Void
}

struct OnboardingView: View {
    @ObservedObject var store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: 520, height: 560)
        .background(Color.dsInk0)
    }

    @ViewBuilder private var content: some View {
        switch store.step {
        case .welcome: welcome
        case .permissions: permissions
        case .hotkey: hotkeyStep
        case .practice: practice
        case .keywords: keywords
        case .done: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Welcome to FreeSpeech")
            body("FreeSpeech turns your voice into text in any app — fully on your Mac, nothing sent to the cloud. Hold a hotkey, speak, and the words appear wherever your cursor is.")
            body("This quick setup grants two permissions, picks your hotkey, and lets you try it once. Takes about a minute.")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Grant two permissions")
            body("FreeSpeech needs these to hear you and to type for you. Both are checked locally by macOS.")
            permissionRow(
                name: "Microphone", granted: store.micGranted,
                detail: "To capture your speech.",
                action: store.requestMic)
            permissionRow(
                name: "Accessibility", granted: store.accessibilityGranted,
                detail: "To insert text into the app you're using, via the global hotkey.",
                action: store.requestAccessibility)
            if !store.permissionsSatisfied {
                body("Grant both to continue. Accessibility opens System Settings — flip FreeSpeech on, and this updates automatically.")
                    .foregroundStyle(Color.dsFaint)
            }
        }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Pick your hotkey")
            body("Hold it to talk, release to insert. Right Option is the default — it's rarely used and never clashes with app shortcuts. You can set a custom combo later in Settings.")
            VStack(spacing: 8) {
                ForEach(HotkeyPreset.all) { preset in
                    Button { store.chooseHotkey(preset) } label: {
                        HStack {
                            Circle()
                                .fill(store.hotkey.id == preset.id ? Color.dsAccent : Color.clear)
                                .overlay(Circle().strokeBorder(
                                    store.hotkey.id == preset.id ? Color.dsAccent : Color.dsFaint, lineWidth: 1.5))
                                .frame(width: 14, height: 14)
                            Text(preset.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.dsPaper)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            store.hotkey.id == preset.id ? Color.dsInk2 : Color.clear,
                            in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                            .strokeBorder(Color.dsLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Try it out")
            if !store.permissionsSatisfied {
                body("Grant Microphone and Accessibility first (go back a step) to try live dictation. You can also skip this.")
                    .foregroundStyle(Color.dsFaint)
            } else if store.practiceRound >= OnboardingStore.practicePrompts.count {
                body("Nice — you've got it. That's exactly how dictation works everywhere: hold, speak, release.")
            } else {
                body("Hold \(store.hotkey.displayName), read this aloud, then release:")
                Text("\u{201C}\(store.currentPrompt)\u{201D}")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPaper)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsInk1, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                        .strokeBorder(Color.dsLine, lineWidth: 1))
                microLabel("Round \(min(store.practiceRound + 1, OnboardingStore.practicePrompts.count)) of \(OnboardingStore.practicePrompts.count)")
            }
            if let heard = store.practiceHeard {
                VStack(alignment: .leading, spacing: 4) {
                    microLabel("Heard")
                    Text(heard)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.dsAccent)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsInk2, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                if store.practiceRound < OnboardingStore.practicePrompts.count {
                    Button("Next phrase") { store.nextPrompt() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private var keywords: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("Teach it your words")
            body("Names, jargon, and product names you say often. FreeSpeech uses these to transcribe them correctly — e.g. proper names or tools like \u{201C}Claude Code\u{201D}.")
            TextEditor(text: $store.vocabularyHint)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color.dsPaper)
                .padding(10)
                .frame(height: 96)
                .background(Color.dsInk2, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                    .strokeBorder(Color.dsLine, lineWidth: 1))
            body("You can edit this anytime in Settings > Vocabulary.")
                .foregroundStyle(Color.dsFaint)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            bigTitle("You're all set")
            body("Hold \(store.hotkey.displayName) anywhere and start talking. FreeSpeech lives in your menu bar — open it for settings, models, and the system-audio hotkey.")
            body("Everything runs on-device. Enjoy.")
        }
    }

    // MARK: Chrome

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FREESPEECH SETUP")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(Color.dsAccent)
                Spacer()
                Text("STEP \(store.stepIndex) / \(store.stepCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(Color.dsMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsInk2)
                    Capsule().fill(Color.dsAccent)
                        .frame(width: geo.size.width * CGFloat(store.stepIndex) / CGFloat(store.stepCount))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }

    private var footer: some View {
        HStack {
            if store.canGoBack {
                Button("Back") { store.back() }.buttonStyle(GhostButtonStyle())
            }
            Button("Skip setup") { store.skipAll() }.buttonStyle(GhostButtonStyle())
            Spacer()
            Button(action: { store.next() }) {
                Text(store.step == .done ? "Start dictating" : "Continue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsInk0)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(primaryEnabled ? Color.dsAccent : Color.dsInk3,
                               in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.dsInk1)
        .overlay(Rectangle().fill(Color.dsLine).frame(height: 1), alignment: .top)
    }

    // Permissions is the only hard gate; everything else is skippable.
    private var primaryEnabled: Bool {
        store.step != .permissions || store.permissionsSatisfied
    }

    private func permissionRow(name: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(granted ? Color.dsAccent : Color.dsFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.dsPaper)
                Text(detail).font(.system(size: 11)).foregroundStyle(Color.dsMuted)
            }
            Spacer()
            if granted {
                Text("GRANTED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).kerning(1)
                    .foregroundStyle(Color.dsAccent)
            } else {
                Button("Grant", action: action).buttonStyle(GhostButtonStyle())
            }
        }
        .padding(12)
        .background(Color.dsInk1, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
            .strokeBorder(Color.dsLine, lineWidth: 1))
    }

    private func bigTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 24, weight: .heavy)).foregroundStyle(Color.dsPaper)
    }
    private func body(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Color.dsMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func microLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced)).kerning(1.2)
            .foregroundStyle(Color.dsMuted)
    }
}

final class OnboardingWindowController {
    private var window: NSWindow?
    private let makeStore: (@escaping () -> Void) -> OnboardingStore

    // makeStore receives the "close the window" action to wire into the store's onFinished.
    init(makeStore: @escaping (@escaping () -> Void) -> OnboardingStore) {
        self.makeStore = makeStore
    }

    func show() {
        if window == nil {
            let store = makeStore { [weak self] in self?.close() }
            let hosting = NSHostingController(rootView: OnboardingView(store: store))
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.info("onboarding window opened")
    }

    func close() {
        window?.close()
        window = nil
    }
}
