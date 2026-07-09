import AppKit
import FreeSpeechCore

// Menu bar icon reflects the pipeline state; menu exposes mode, hotkey, model, quit.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: Settings
    var onSettingsChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var currentState: DictationState = .idle
    private var statusLine: String = "Idle"

    init(settings: Settings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        update(state: .idle)
    }

    func update(state: DictationState) {
        currentState = state
        let (symbol, description, line): (String, String, String)
        switch state {
        case .idle:
            (symbol, description, line) = ("mic", "FreeSpeech idle", "Idle — hold \(settings.hotkey.displayName)")
        case .recording:
            (symbol, description, line) = ("mic.fill", "FreeSpeech recording", "Recording…")
        case .transcribing:
            (symbol, description, line) = ("waveform", "FreeSpeech transcribing", "Transcribing…")
        case .error(let message):
            (symbol, description, line) = ("mic.slash", "FreeSpeech error", "Error: \(message)")
        }
        statusLine = line
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: symbol, accessibilityDescription: description)
            button.toolTip = line
        }
    }

    // Rebuild each time it opens so checkmarks and model list stay fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in ActivationMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Activation", action: nil, keyEquivalent: "")
        menu.addItem(modeItem)
        menu.setSubmenu(modeMenu, for: modeItem)

        let hotkeyMenu = NSMenu()
        for preset in HotkeyPreset.all {
            let item = NSMenuItem(
                title: preset.displayName, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = settings.hotkey == preset ? .on : .off
            hotkeyMenu.addItem(item)
        }
        let hotkeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        menu.addItem(hotkeyItem)
        menu.setSubmenu(hotkeyMenu, for: hotkeyItem)

        let modelMenu = NSMenu()
        let installed = AppPaths.installedModels()
        if installed.isEmpty {
            let none = NSMenuItem(
                title: "No models found — run ./build.sh", action: nil, keyEquivalent: "")
            none.isEnabled = false
            modelMenu.addItem(none)
        }
        for model in installed {
            let item = NSMenuItem(
                title: model, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            item.state = settings.modelName == model ? .on : .off
            modelMenu.addItem(item)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        menu.addItem(modelItem)
        menu.setSubmenu(modelMenu, for: modelItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let logItem = NSMenuItem(title: "View Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        let quit = NSMenuItem(title: "Quit FreeSpeech", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ActivationMode(rawValue: raw) else { return }
        settings.mode = mode
        Log.info("settings changed: mode=\(mode.rawValue)")
        onSettingsChanged?()
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = HotkeyPreset.find(id: id) else { return }
        settings.hotkey = preset
        Log.info("settings changed: hotkey=\(preset.id)")
        onSettingsChanged?()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        settings.modelName = model
        Log.info("settings changed: model=\(model)")
        onSettingsChanged?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppPaths.logFile)
    }

    @objc private func quitApp() {
        Log.info("quit requested from menu")
        NSApp.terminate(nil)
    }
}
