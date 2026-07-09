import Foundation

public struct HotkeyPreset: Equatable, Identifiable {
    public enum Kind: String { case modifier, key }
    public let id: String
    public let displayName: String
    public let keyCode: Int64
    public let kind: Kind

    // Right Option default: rarely used alone, never conflicts with app shortcuts,
    // and a modifier key allows true push-to-talk hold semantics.
    public static let rightOption = HotkeyPreset(
        id: "rightOption", displayName: "Right Option (hold)", keyCode: 61, kind: .modifier)
    public static let rightCommand = HotkeyPreset(
        id: "rightCommand", displayName: "Right Command (hold)", keyCode: 54, kind: .modifier)
    public static let f13 = HotkeyPreset(
        id: "f13", displayName: "F13", keyCode: 105, kind: .key)

    public static let all: [HotkeyPreset] = [.rightOption, .rightCommand, .f13]

    public static func find(id: String) -> HotkeyPreset? {
        all.first { $0.id == id }
    }

    // Any key the user records in settings becomes a custom preset; hold semantics
    // (push-to-talk) work for both bare modifiers and regular keys.
    public static func custom(keyCode: Int64) -> HotkeyPreset {
        HotkeyPreset(
            id: "custom",
            displayName: KeyNames.name(forKeyCode: keyCode),
            keyCode: keyCode,
            kind: KeyNames.isModifier(keyCode) ? .modifier : .key)
    }
}

public final class Settings {
    private let defaults: UserDefaults

    private enum Key {
        static let mode = "activationMode"
        static let hotkey = "hotkeyPresetID"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let model = "modelName"
        static let maxRecordingSeconds = "maxRecordingSeconds"
        static let postProcessing = "postProcessingMode"
        static let tone = "rewriteTone"
        static let vocabularyHint = "vocabularyHint"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: ActivationMode {
        get { defaults.string(forKey: Key.mode).flatMap(ActivationMode.init) ?? .pushToTalk }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    public var hotkey: HotkeyPreset {
        get {
            let id = defaults.string(forKey: Key.hotkey)
            if id == "custom", defaults.object(forKey: Key.hotkeyKeyCode) != nil {
                return .custom(keyCode: Int64(defaults.integer(forKey: Key.hotkeyKeyCode)))
            }
            return id.flatMap(HotkeyPreset.find) ?? .rightOption
        }
        set {
            defaults.set(newValue.id, forKey: Key.hotkey)
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
        }
    }

    public var postProcessing: PostProcessingMode {
        get { defaults.string(forKey: Key.postProcessing).flatMap(PostProcessingMode.init) ?? .cleanup }
        set { defaults.set(newValue.rawValue, forKey: Key.postProcessing) }
    }

    public var tone: RewriteTone {
        get { defaults.string(forKey: Key.tone).flatMap(RewriteTone.init) ?? .professional }
        set { defaults.set(newValue.rawValue, forKey: Key.tone) }
    }

    // Fed to whisper as an initial prompt to bias proper nouns the user actually says.
    // This phrasing benchmarked best: names as a list plus the key term in a sentence.
    public var vocabularyHint: String {
        get {
            defaults.string(forKey: Key.vocabularyHint)
                ?? "Caden Warren, Claude Code, FreeSpeech. My specialty is to use Claude Code on projects."
        }
        set { defaults.set(newValue, forKey: Key.vocabularyHint) }
    }

    // large-v3-turbo-q5_0 won the bench/results.json matrix: best WER (12.9% on the
    // reference clip, with proper nouns right) at ~0.6s per 23s of audio on M4 Max.
    public var modelName: String {
        get { defaults.string(forKey: Key.model) ?? "large-v3-turbo-q5_0" }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    public var maxRecordingSeconds: Double {
        get {
            let v = defaults.double(forKey: Key.maxRecordingSeconds)
            return v > 0 ? v : 60
        }
        set { defaults.set(newValue, forKey: Key.maxRecordingSeconds) }
    }
}

public enum AppPaths {
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeSpeech", isDirectory: true)
    }
    public static var modelsDir: URL {
        appSupport.appendingPathComponent("models", isDirectory: true)
    }
    public static var logFile: URL {
        appSupport.appendingPathComponent("freespeech.log")
    }
    public static func modelFile(named name: String) -> URL {
        modelsDir.appendingPathComponent("ggml-\(name).bin")
    }
    public static func installedModels() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path)) ?? []
        return files.compactMap { f in
            guard f.hasPrefix("ggml-"), f.hasSuffix(".bin") else { return nil }
            return String(f.dropFirst("ggml-".count).dropLast(".bin".count))
        }.sorted()
    }
}
