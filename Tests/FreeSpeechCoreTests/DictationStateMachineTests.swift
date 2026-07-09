import XCTest
@testable import FreeSpeechCore

final class DictationStateMachineTests: XCTestCase {
    func testPushToTalkHappyPath() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .pushToTalk), .startRecording)
        XCTAssertEqual(m.state, .recording)
        XCTAssertEqual(m.handle(.hotkeyUp, mode: .pushToTalk), .stopAndTranscribe)
        XCTAssertEqual(m.state, .transcribing)
        XCTAssertEqual(m.handle(.transcriptionSucceeded, mode: .pushToTalk), .becameIdle)
        XCTAssertEqual(m.state, .idle)
    }

    func testToggleHappyPath() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .toggle), .startRecording)
        XCTAssertEqual(m.handle(.hotkeyUp, mode: .toggle), .none)
        XCTAssertEqual(m.state, .recording)
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .toggle), .stopAndTranscribe)
        XCTAssertEqual(m.state, .transcribing)
    }

    func testPressesDuringTranscribingAreIgnored() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        _ = m.handle(.hotkeyUp, mode: .pushToTalk)
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .pushToTalk), .none)
        XCTAssertEqual(m.handle(.hotkeyUp, mode: .pushToTalk), .none)
        XCTAssertEqual(m.state, .transcribing)
    }

    func testDoubleDownIsIgnoredInPushToTalk() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .pushToTalk), .none)
        XCTAssertEqual(m.state, .recording)
    }

    func testStrayUpInIdleIsIgnored() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.hotkeyUp, mode: .pushToTalk), .none)
        XCTAssertEqual(m.state, .idle)
    }

    func testMaxDurationStopsRecording() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        XCTAssertEqual(m.handle(.recordingTimedOut, mode: .pushToTalk), .stopAndTranscribe)
        XCTAssertEqual(m.state, .transcribing)
    }

    func testTranscriptionFailureSurfacesErrorThenRecovers() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        _ = m.handle(.hotkeyUp, mode: .pushToTalk)
        XCTAssertEqual(
            m.handle(.transcriptionFailed("model load failed"), mode: .pushToTalk),
            .showError("model load failed"))
        XCTAssertEqual(m.state, .error("model load failed"))
        XCTAssertEqual(m.handle(.errorDismissed, mode: .pushToTalk), .becameIdle)
        XCTAssertEqual(m.state, .idle)
    }

    func testHotkeyDownInErrorStateStartsFreshRecording() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        _ = m.handle(.recordingFailed("audio device init failed"), mode: .pushToTalk)
        XCTAssertEqual(m.state, .error("audio device init failed"))
        XCTAssertEqual(m.handle(.hotkeyDown, mode: .pushToTalk), .startRecording)
        XCTAssertEqual(m.state, .recording)
    }

    func testRecordingFailureAbortsToError() {
        var m = DictationStateMachine()
        _ = m.handle(.hotkeyDown, mode: .pushToTalk)
        XCTAssertEqual(
            m.handle(.recordingFailed("no input device"), mode: .pushToTalk),
            .abortRecording("no input device"))
        XCTAssertEqual(m.state, .error("no input device"))
    }
}
