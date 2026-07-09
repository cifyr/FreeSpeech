import AppKit
import FreeSpeechCore

enum TextInserterError: LocalizedError {
    case eventCreationFailed

    var errorDescription: String? {
        "Could not synthesize Cmd+V — check Accessibility permission"
    }
}

// Clipboard + synthesized Cmd+V: the one insertion path that works across native,
// Electron, web, and terminal apps alike. Prior clipboard is always restored.
final class TextInserter {
    private static let clipboardRestoreDelay: TimeInterval = 0.7

    func insert(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let target = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        Log.info("inserting \(text.count) chars into frontmost app \"\(target)\" via clipboard+Cmd+V")

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        do {
            try synthesizePaste()
        } catch {
            restore(saved, to: pasteboard)
            throw error
        }

        // Restore after the target app has consumed the paste event.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipboardRestoreDelay) { [weak self] in
            self?.restore(saved, to: pasteboard)
            Log.info("clipboard restored (\(saved.count) item(s))")
        }
    }

    private func synthesizePaste() throws {
        // If the push-to-talk modifier is still physically held, its flag would merge
        // into the synthetic event and turn Cmd+V into Cmd+Opt+V. Wait for release.
        let deadline = CFAbsoluteTimeGetCurrent() + 0.5
        while CFAbsoluteTimeGetCurrent() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand]).isEmpty {
                break
            }
            usleep(20_000)
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            throw TextInserterError.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
