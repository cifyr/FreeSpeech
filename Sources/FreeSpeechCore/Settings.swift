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
}

public final class Settings {
    private let defaults: UserDefaults

    private enum Key {
        static let mode = "activationMode"
        static let hotkey = "hotkeyPresetID"
        static let model = "modelName"
        static let maxRecordingSeconds = "maxRecordingSeconds"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: ActivationMode {
        get { defaults.string(forKey: Key.mode).flatMap(ActivationMode.init) ?? .pushToTalk }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    public var hotkey: HotkeyPreset {
        get { defaults.string(forKey: Key.hotkey).flatMap(HotkeyPreset.find) ?? .rightOption }
        set { defaults.set(newValue.id, forKey: Key.hotkey) }
    }

    // base.en: smallest model that is accurate enough for dictation and comfortably
    // beats the 2s latency bar on Apple Silicon. Swappable from the menu.
    public var modelName: String {
        get { defaults.string(forKey: Key.model) ?? "base.en" }
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
