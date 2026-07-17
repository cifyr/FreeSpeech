import AppKit
import FreeKitCore

enum EventTapError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        "Could not install the global hotkey listener — Accessibility permission is required"
    }
}

// A module that rewrites raw keyboard events (the HyperKey remap). Runs before
// hotkey matching so remapped flags are what recognizers see.
protocol EventRewriter: AnyObject {
    // May mutate the event in place; return .swallow to drop it entirely.
    func rewrite(kind: HotkeyRecognizer.EventKind, event: CGEvent) -> EventRewriteVerdict
}

enum EventRewriteVerdict {
    case pass
    case swallow
}

// The suite's single active CGEventTap. One tap instead of one per hotkey: taps
// are a scarce, failure-prone resource (macOS disables stalled ones), and
// multiple active taps ordering against each other is undefined. All global
// hotkeys and the HyperKey remap funnel through here.
//
// The tap runs on its OWN dedicated thread/run loop, not the main run loop.
// macOS disables a tap whose run loop doesn't service events within ~1s, so
// hosting it on main meant any main-thread stall (Notebook's synchronous Apple
// Notes AppleScript, model load, a SwiftUI hitch) could drop the keypress that
// arrived during the stall — the "hotkey sometimes doesn't fire" bug. On its
// own user-interactive thread the tap stays responsive regardless of main.
final class EventTapHub {
    final class HotkeyToken {
        fileprivate let recognizer: HotkeyRecognizer
        fileprivate let onEvent: (HotkeyRecognizer.Direction) -> Void
        fileprivate let label: String

        fileprivate init(recognizer: HotkeyRecognizer, label: String,
                         onEvent: @escaping (HotkeyRecognizer.Direction) -> Void) {
            self.recognizer = recognizer
            self.label = label
            self.onEvent = onEvent
        }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var tokens: [HotkeyToken] = []
    private var rewriters: [EventRewriter] = []
    // Guards tokens/rewriters/recognizer state and the tap handles, all of which
    // are now touched from both the tap thread (handle) and main (register/etc.).
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return tapThread != nil
    }

    // Registrations are accepted any time; they take effect once the tap starts
    // (Accessibility can be granted after launch).
    func register(preset: HotkeyPreset, label: String,
                  onEvent: @escaping (HotkeyRecognizer.Direction) -> Void) -> HotkeyToken {
        let token = HotkeyToken(
            recognizer: HotkeyRecognizer(preset: preset), label: label, onEvent: onEvent)
        lock.lock()
        tokens.append(token)
        lock.unlock()
        Log.info("hotkey registered: \(label) = \(preset.displayName) [keyCode \(preset.keyCode)]")
        return token
    }

    func unregister(_ token: HotkeyToken) {
        lock.lock()
        tokens.removeAll { $0 === token }
        lock.unlock()
    }

    func update(_ token: HotkeyToken, preset: HotkeyPreset) {
        lock.lock()
        token.recognizer.reset(preset: preset)
        lock.unlock()
        Log.info("hotkey updated: \(token.label) = \(preset.displayName) [keyCode \(preset.keyCode)]")
    }

    func addRewriter(_ rewriter: EventRewriter) {
        lock.lock()
        if !rewriters.contains(where: { $0 === rewriter }) { rewriters.append(rewriter) }
        lock.unlock()
    }

    func removeRewriter(_ rewriter: EventRewriter) {
        lock.lock()
        rewriters.removeAll { $0 === rewriter }
        lock.unlock()
    }

    func start() throws {
        if isRunning { return }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        // Install the tap on the dedicated thread and only return once it's up
        // (or failed), so start() keeps its synchronous throwing contract.
        let ready = DispatchSemaphore(value: 0)
        var installError: Error?
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            do {
                try self.installTap(mask: mask)
            } catch {
                installError = error
                ready.signal()
                return
            }
            ready.signal()
            // Keep this thread's run loop alive to service the tap until stop().
            CFRunLoopRun()
        }
        thread.name = "com.cadenwarren.freekit.eventtap"
        thread.qualityOfService = .userInteractive
        lock.lock(); tapThread = thread; lock.unlock()
        thread.start()
        ready.wait()
        if let installError {
            lock.lock(); tapThread = nil; lock.unlock()
            throw installError
        }
        lock.lock(); let n = tokens.count, r = rewriters.count; lock.unlock()
        Log.info("event tap hub started (\(n) hotkeys, \(r) rewriters, dedicated thread)")
    }

    // Runs on the tap thread: creates the tap and wires it to this thread's loop.
    private func installTap(mask: CGEventMask) throws {
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
                let hub = Unmanaged<EventTapHub>.fromOpaque(userInfo).takeUnretainedValue()
                return hub.handle(type: type, event: event)
                    ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            throw EventTapError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let rl = CFRunLoopGetCurrent()
        lock.lock()
        self.tap = tap
        self.runLoopSource = source
        self.tapRunLoop = rl
        lock.unlock()
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let rl = self.tapRunLoop
        let src = self.runLoopSource
        self.tap = nil
        self.runLoopSource = nil
        self.tapRunLoop = nil
        self.tapThread = nil
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        // CFRunLoopStop/RemoveSource are safe to call from another thread; this
        // ends the dedicated thread's CFRunLoopRun so it exits cleanly.
        if let rl {
            if let src { CFRunLoopRemoveSource(rl, src, .commonModes) }
            CFRunLoopStop(rl)
        }
    }

    // Returns true when the event must not reach other apps. Runs on the tap thread.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables taps that stall or when the user triggers Secure Input;
        // re-enabling here is what keeps the hotkeys firing forever.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let tap = self.tap; lock.unlock()
            if let tap {
                Log.error("event tap disabled by system (\(type.rawValue)), re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let kind: HotkeyRecognizer.EventKind
        switch type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return false
        }

        lock.lock()
        defer { lock.unlock() }

        // Rewriters (the HyperKey Caps Lock -> Hyper remap) must keep running even while
        // a recorder is capturing: the recorder's local NSEvent monitor only
        // sees Hyper-key chords because this rewrite already folded the hold
        // flags in. Skipping it here made Hyper combos impossible to record.
        for rewriter in rewriters {
            if case .swallow = rewriter.rewrite(kind: kind, event: event) {
                return true
            }
        }

        // The focused recorder's local monitor must receive the (possibly
        // rewritten) event, but no already-registered hotkey may fire while
        // it's active — otherwise recording a new binding could trigger an
        // old one mid-capture.
        if ShortcutCaptureGate.isActive {
            for token in tokens {
                token.recognizer.reset(preset: token.recognizer.preset)
            }
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Every recognizer sees every event so their held-state machines stay
        // consistent; the event is swallowed if any of them claims it.
        var swallow = false
        for token in tokens {
            switch token.recognizer.handle(
                kind: kind, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat) {
            case .pass:
                break
            case .swallow:
                swallow = true
            case .fire(let direction, let swallowEvent):
                swallow = swallow || swallowEvent
                dispatch(token, direction)
            }
        }
        return swallow
    }

    private func dispatch(_ token: HotkeyToken, _ direction: HotkeyRecognizer.Direction) {
        Log.info("hotkey fired: \(token.label) \(direction)")
        // Hop to main: token callbacks touch AppKit windows and module state.
        DispatchQueue.main.async {
            token.onEvent(direction)
        }
    }
}
