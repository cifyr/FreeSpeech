import AppKit
import SwiftUI
import FreeSpeechCore

final class SettingsStore: ObservableObject {
    // SwiftUI also declares a `Settings` scene type, hence the qualified name.
    private let settings: FreeSpeechCore.Settings
    private let onHotkeyChanged: () -> Void
    private let onModelChanged: () -> Void
    private var captureMonitor: Any?

    @Published var mode: ActivationMode { didSet { settings.mode = mode } }
    @Published var hotkey: HotkeyPreset {
        didSet {
            settings.hotkey = hotkey
            onHotkeyChanged()
        }
    }
    @Published var modelName: String {
        didSet {
            settings.modelName = modelName
            onModelChanged()
        }
    }
    @Published var postProcessing: PostProcessingMode { didSet { settings.postProcessing = postProcessing } }
    @Published var tone: RewriteTone { didSet { settings.tone = tone } }
    @Published var vocabularyHint: String { didSet { settings.vocabularyHint = vocabularyHint } }
    @Published var isCapturingShortcut = false
    @Published var installedModels: [String] = []

    let languageModelAvailable: Bool

    init(settings: FreeSpeechCore.Settings, languageModelAvailable: Bool,
         onHotkeyChanged: @escaping () -> Void, onModelChanged: @escaping () -> Void) {
        self.settings = settings
        self.languageModelAvailable = languageModelAvailable
        self.onHotkeyChanged = onHotkeyChanged
        self.onModelChanged = onModelChanged
        _mode = Published(initialValue: settings.mode)
        _hotkey = Published(initialValue: settings.hotkey)
        _modelName = Published(initialValue: settings.modelName)
        _postProcessing = Published(initialValue: settings.postProcessing)
        _tone = Published(initialValue: settings.tone)
        _vocabularyHint = Published(initialValue: settings.vocabularyHint)
        refreshModels()
    }

    func refreshModels() {
        installedModels = AppPaths.installedModels()
    }

    // Captures the next key press (regular or bare modifier) as the hotkey. Esc cancels.
    func beginShortcutCapture() {
        guard captureMonitor == nil else { return }
        isCapturingShortcut = true
        Log.info("shortcut capture started")
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let code = Int64(event.keyCode)
            switch event.type {
            case .keyDown:
                if code != 53 {  // Esc cancels without saving
                    self.capture(code)
                } else {
                    self.endShortcutCapture()
                }
                return nil
            case .flagsChanged:
                // Only the press (flags present), not the release.
                if KeyNames.isModifier(code),
                   !event.modifierFlags.intersection([.command, .option, .shift, .control, .function]).isEmpty {
                    self.capture(code)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    func endShortcutCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
        captureMonitor = nil
        isCapturingShortcut = false
    }

    private func capture(_ keyCode: Int64) {
        endShortcutCapture()
        let preset = HotkeyPreset.custom(keyCode: keyCode)
        Log.info("shortcut captured: \(preset.displayName) [keyCode \(keyCode)]")
        hotkey = preset
    }
}

// Greenlight-styled settings: ink surfaces, hairlines, mono micro labels, red accent.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                card {
                    sectionLabel("Activation")
                    HStack(spacing: 8) {
                        ForEach(ActivationMode.allCases, id: \.self) { mode in
                            chip(mode.displayName, selected: store.mode == mode) {
                                store.mode = mode
                            }
                        }
                    }
                    Divider().overlay(Color.dsLine).padding(.vertical, 4)
                    sectionLabel("Hotkey")
                    HStack(spacing: 10) {
                        Text(store.isCapturingShortcut ? "PRESS A KEY\u{2026}" : store.hotkey.displayName.uppercased())
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .kerning(0.8)
                            .foregroundStyle(store.isCapturingShortcut ? Color.dsAccent : Color.dsPaper)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Color.dsInk2, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                                    .strokeBorder(store.isCapturingShortcut ? Color.dsAccent : Color.dsLine, lineWidth: 1))
                        Button(store.isCapturingShortcut ? "Cancel" : "Record Shortcut") {
                            store.isCapturingShortcut ? store.endShortcutCapture() : store.beginShortcutCapture()
                        }
                        .buttonStyle(GhostButtonStyle())
                        Spacer()
                    }
                    Text("Hold it to talk, or press to start and stop in toggle mode. Bare modifier keys like Right Option work.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
                card {
                    sectionLabel("Model")
                    if store.installedModels.isEmpty {
                        Text("No models installed — run ./build.sh")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsMuted)
                    }
                    ForEach(store.installedModels, id: \.self) { model in
                        selectableRow(
                            title: model,
                            subtitle: modelSubtitle(model),
                            selected: store.modelName == model
                        ) { store.modelName = model }
                    }
                }
                card {
                    sectionLabel("Post-processing")
                    ForEach(PostProcessingMode.allCases, id: \.self) { mode in
                        selectableRow(
                            title: mode.displayName,
                            subtitle: mode.detail,
                            selected: store.postProcessing == mode,
                            disabled: mode.needsLanguageModel && !store.languageModelAvailable
                        ) { store.postProcessing = mode }
                    }
                    if !store.languageModelAvailable {
                        Text("Apple Intelligence is unavailable, so on-device rewrite modes are disabled. Enable it in System Settings > Apple Intelligence & Siri.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsFaint)
                    }
                    if store.postProcessing == .tone {
                        HStack(spacing: 8) {
                            ForEach(RewriteTone.allCases, id: \.self) { tone in
                                chip(tone.displayName, selected: store.tone == tone) {
                                    store.tone = tone
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                card {
                    sectionLabel("Vocabulary")
                    TextField("Names and terms you often say", text: $store.vocabularyHint)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsPaper)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Color.dsInk2, in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                                .strokeBorder(Color.dsLine, lineWidth: 1))
                    Text("Steers transcription toward names and jargon you use, e.g. \"Caden Warren, Claude Code\".")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 620)
        .background(Color.dsInk0)
        .onDisappear { store.endShortcutCapture() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FREESPEECH")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(Color.dsAccent)
            Text("Settings")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Color.dsPaper)
        }
        .padding(.top, 8)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.dsInk1, in: RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous)
                    .strokeBorder(Color.dsLine, lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .kerning(1.2)
            .foregroundStyle(Color.dsMuted)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.dsAccent : Color.dsPaper)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.dsInk2, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? Color.dsAccent.opacity(0.6) : Color.dsLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func selectableRow(
        title: String, subtitle: String, selected: Bool,
        disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(selected ? Color.dsAccent : Color.clear)
                    .overlay(Circle().strokeBorder(
                        selected ? Color.dsAccent : Color.dsFaint, lineWidth: 1.5))
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(disabled ? Color.dsFaint : Color.dsPaper)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(
                selected ? Color.dsInk3 : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func modelSubtitle(_ model: String) -> String {
        let url = AppPaths.modelFile(named: model)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        let size = bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        return size.isEmpty ? "whisper ggml model" : "whisper ggml model, \(size)"
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let makeStore: () -> SettingsStore

    init(makeStore: @escaping () -> SettingsStore) {
        self.makeStore = makeStore
    }

    func show() {
        if window == nil {
            let store = makeStore()
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)  // Greenlight is dark-only
            w.backgroundColor = DS.ink0
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.info("settings window opened")
    }
}
