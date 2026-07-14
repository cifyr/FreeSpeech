import XCTest
@testable import FreeSpeechCore

final class IcePlanTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: Settings!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.cadenwarren.freespeech.tests.ice")!
        defaults.removePersistentDomain(forName: "com.cadenwarren.freespeech.tests.ice")
        settings = Settings(defaults: defaults)
    }

    func testHiddenSetDefaultsEmpty() {
        XCTAssertTrue(settings.iceHiddenBundleIDs.isEmpty)
        XCTAssertFalse(settings.iceIsHidden(bundleID: "com.example.app"))
    }

    func testHideAndRevealRoundTrip() {
        settings.setIceHidden(true, bundleID: "com.example.app")
        XCTAssertTrue(Settings(defaults: defaults).iceIsHidden(bundleID: "com.example.app"))

        settings.setIceHidden(false, bundleID: "com.example.app")
        XCTAssertFalse(Settings(defaults: defaults).iceIsHidden(bundleID: "com.example.app"))
    }

    func testHiddenSetTracksMultipleApps() {
        settings.setIceHidden(true, bundleID: "com.example.one")
        settings.setIceHidden(true, bundleID: "com.example.two")
        settings.setIceHidden(false, bundleID: "com.example.one")

        let restored = Settings(defaults: defaults).iceHiddenBundleIDs
        XCTAssertEqual(restored, ["com.example.two"])
    }

    func testDragTargetHidingSitsLeftOfAnchorByHalfWidthPlusMargin() {
        let target = IceBoundary.dragTarget(anchorMinX: 500, itemWidth: 24, hiding: true)
        XCTAssertEqual(target, 500 - 12 - 4)
    }

    func testDragTargetRevealingSitsRightOfAnchorByHalfWidthPlusMargin() {
        let target = IceBoundary.dragTarget(anchorMinX: 500, itemWidth: 24, hiding: false)
        XCTAssertEqual(target, 500 + 12 + 4)
    }

    func testIsHiddenWhenCenterAtOrLeftOfAnchor() {
        let anchorMinX: CGFloat = 500
        XCTAssertTrue(IceBoundary.isHidden(
            itemFrame: CGRect(x: 470, y: 0, width: 20, height: 22), anchorMinX: anchorMinX))
        XCTAssertTrue(IceBoundary.isHidden(
            itemFrame: CGRect(x: 490, y: 0, width: 20, height: 22), anchorMinX: anchorMinX))
    }

    func testIsNotHiddenWhenCenterRightOfAnchor() {
        let anchorMinX: CGFloat = 500
        XCTAssertFalse(IceBoundary.isHidden(
            itemFrame: CGRect(x: 510, y: 0, width: 20, height: 22), anchorMinX: anchorMinX))
    }
}
