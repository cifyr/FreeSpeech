import AppKit
import FreeSpeechCore

let arguments = CommandLine.arguments

if arguments.contains("--transcribe-file") {
    exit(TranscribeFileCommand.run(arguments: arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar-only app: no Dock icon, never takes focus from the app being dictated into.
app.setActivationPolicy(.accessory)
app.run()
