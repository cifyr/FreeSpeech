import AppKit
import FreeSpeechCore

enum HotkeyError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        "Could not install the global hotkey listener — Accessibility permission is required"
    }
}

// Listen-only CGEventTap: works system-wide regardless of which app is focused,
// and supports hold semantics for bare modifier keys (which Carbon hotkeys cannot).
final class HotkeyManager {
    enum Direction { case down, up }
    var onEvent: ((Direction) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var preset: HotkeyPreset = .rightOption
    private var modifierIsDown = false
    private var comboIsDown = false
    // The combo ended by modifier release but the key is still physically down:
    // its remaining repeats and final key-up must not leak to the app.
    private var awaitingKeyUp = false

    func start(preset: HotkeyPreset) throws {
        stop()
        self.preset = preset
        self.modifierIsDown = false
        self.comboIsDown = false
        self.awaitingKeyUp = false

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        // Active (not listen-only) tap: hotkey key events must be swallowed so a
        // combo like Cmd+K never reaches the frontmost app. Everything else passes.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                let swallow = manager.handle(type: type, event: event)
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.info("hotkey listener installed: \(preset.displayName) [keyCode \(preset.keyCode)]")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // Returns true when the event belongs to the hotkey and must not reach apps.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables taps that stall or when the user triggers Secure Input;
        // re-enabling here is what keeps the hotkey firing forever.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                Log.error("event tap disabled by system (\(type.rawValue)), re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let required = CGEventFlags(rawValue: preset.modifiers.rawValue)

        switch (preset.kind, type) {
        case (.modifier, .flagsChanged):
            guard keyCode == preset.keyCode else { return false }
            let flagBit = Self.flagBit(forKeyCode: preset.keyCode)
            let isDown = event.flags.contains(flagBit)
            guard isDown != modifierIsDown else { return false }  // debounce duplicate flag events
            modifierIsDown = isDown
            dispatch(isDown ? .down : .up)
            // Bare-modifier flag changes stay visible to the system (harmless alone).
            return false

        case (.key, .keyDown):
            guard keyCode == preset.keyCode else { return false }
            // While the combo is held (push-to-talk), the key autorepeats: every
            // one of those must be swallowed or the app underneath receives a
            // stream of e.g. Cmd+= presses while the user is dictating.
            if comboIsDown || awaitingKeyUp { return true }
            guard event.flags.intersection(Self.relevantFlags) == required else { return false }
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            comboIsDown = true
            dispatch(.down)
            return true

        case (.key, .keyUp):
            guard keyCode == preset.keyCode else { return false }
            if awaitingKeyUp {
                awaitingKeyUp = false
                return true
            }
            guard comboIsDown else { return false }
            comboIsDown = false
            dispatch(.up)
            return true

        case (.key, .flagsChanged):
            // Push-to-talk on a combo: releasing a required modifier before the key
            // (e.g. Cmd before = in Cmd+=) must still count as release, and the
            // still-held key is then muted until its own key-up.
            if comboIsDown, !event.flags.intersection(Self.relevantFlags).contains(required) {
                comboIsDown = false
                awaitingKeyUp = true
                dispatch(.up)
            }
            return false

        default:
            return false
        }
    }

    private static let relevantFlags: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn]

    private func dispatch(_ direction: Direction) {
        Log.info("hotkey fired: \(direction)")
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(direction)
        }
    }

    static func flagBit(forKeyCode keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 58, 61: return .maskAlternate
        case 56, 60: return .maskShift
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return []
        }
    }
}
