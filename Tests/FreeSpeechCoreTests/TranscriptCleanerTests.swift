import XCTest
@testable import FreeSpeechCore

final class TranscriptCleanerTests: XCTestCase {
    func testTrimsWhitespace() {
        XCTAssertEqual(TranscriptCleaner.clean("  Hello world. \n"), "Hello world.")
    }

    func testCapitalizesFirstLetter() {
        XCTAssertEqual(TranscriptCleaner.clean("hello there"), "Hello there")
    }

    func testBlankAudioMarkerYieldsNil() {
        XCTAssertNil(TranscriptCleaner.clean(" [BLANK_AUDIO]"))
        XCTAssertNil(TranscriptCleaner.clean("(wind blowing)"))
        XCTAssertNil(TranscriptCleaner.clean("♪♪"))
    }

    func testEmptyYieldsNil() {
        XCTAssertNil(TranscriptCleaner.clean(""))
        XCTAssertNil(TranscriptCleaner.clean("   \n "))
    }

    func testMarkerInsideSpeechIsStripped() {
        XCTAssertEqual(
            TranscriptCleaner.clean("send the report [BLANK_AUDIO] by Friday"),
            "Send the report by Friday")
    }

    func testCollapsesInternalWhitespace() {
        XCTAssertEqual(TranscriptCleaner.clean("one  two\n three"), "One two three")
    }

    func testAlreadyCleanTextUnchanged() {
        XCTAssertEqual(
            TranscriptCleaner.clean("The quick brown fox."),
            "The quick brown fox.")
    }
}
