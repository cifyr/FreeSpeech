import Foundation

public enum ActivationMode: String, CaseIterable {
    case pushToTalk
    case toggle

    public var displayName: String {
        switch self {
        case .pushToTalk: return "Push to talk (hold)"
        case .toggle: return "Toggle (press twice)"
        }
    }
}

public enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case error(String)
}

public enum DictationEvent: Equatable {
    case hotkeyDown
    case hotkeyUp
    case recordingTimedOut
    case recordingFailed(String)
    case transcriptionSucceeded
    case transcriptionFailed(String)
    case errorDismissed
}

public enum DictationAction: Equatable {
    case startRecording
    case stopAndTranscribe
    case abortRecording(String)
    case showError(String)
    case becameIdle
    case none
}

// Pure transition logic so double-triggers and mid-transcription presses are
// provably ignored; the app layer executes the returned action.
public struct DictationStateMachine {
    public private(set) var state: DictationState = .idle

    public init() {}

    public mutating func handle(_ event: DictationEvent, mode: ActivationMode) -> DictationAction {
        switch (state, event) {
        case (.idle, .hotkeyDown), (.error, .hotkeyDown):
            state = .recording
            return .startRecording

        case (.recording, .hotkeyUp) where mode == .pushToTalk,
             (.recording, .hotkeyDown) where mode == .toggle,
             (.recording, .recordingTimedOut):
            state = .transcribing
            return .stopAndTranscribe

        case (.recording, .recordingFailed(let reason)):
            state = .error(reason)
            return .abortRecording(reason)

        case (.transcribing, .transcriptionSucceeded):
            state = .idle
            return .becameIdle

        case (.transcribing, .transcriptionFailed(let reason)):
            state = .error(reason)
            return .showError(reason)

        case (.error, .errorDismissed):
            state = .idle
            return .becameIdle

        // Guards: presses while transcribing, stray key-ups, repeated downs in
        // push-to-talk, key-ups in toggle mode — all ignored.
        default:
            return .none
        }
    }
}
