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

    func start(preset: HotkeyPreset) throws {
        stop()
        self.preset = preset
        self.modifierIsDown = false

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                    manager.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
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

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps that stall or when the user triggers Secure Input;
        // re-enabling here is what keeps the hotkey firing forever.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                Log.error("event tap disabled by system (\(type.rawValue)), re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == preset.keyCode else { return }

        switch (preset.kind, type) {
        case (.modifier, .flagsChanged):
            let flagBit = Self.flagBit(forKeyCode: preset.keyCode)
            let isDown = event.flags.contains(flagBit)
            guard isDown != modifierIsDown else { return }  // debounce duplicate flag events
            modifierIsDown = isDown
            dispatch(isDown ? .down : .up)

        case (.key, .keyDown):
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            dispatch(.down)

        case (.key, .keyUp):
            dispatch(.up)

        default:
            break
        }
    }

    private func dispatch(_ direction: Direction) {
        Log.info("hotkey fired: \(direction)")
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(direction)
        }
    }

    private static func flagBit(forKeyCode keyCode: Int64) -> CGEventFlags {
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
