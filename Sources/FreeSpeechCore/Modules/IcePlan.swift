import Foundation
import CoreGraphics

// One third-party app currently owning a menu bar item. AppKit-free: the icon
// image and click handling stay in the app-side scanner, this just carries
// enough to group items by app and compute where to drag them.
public struct MenuBarAppEntry: Identifiable, Equatable {
    public var id: String { bundleID ?? "pid-\(pid)" }
    public let pid: Int32
    // nil for the rare process with no bundle (e.g. a bare command-line tool
    // that raised a status item) — falls back to pid-keyed identity/persistence
    // for that process only, so it won't survive a relaunch, unlike the
    // common case.
    public let bundleID: String?
    public let displayName: String
    public let frame: CGRect

    public init(pid: Int32, bundleID: String?, displayName: String, frame: CGRect) {
        self.pid = pid
        self.bundleID = bundleID
        self.displayName = displayName
        self.frame = frame
    }
}

// Boundary math for hiding: an app's item is "hidden" once it sits left of
// FreeKit's own anchor item, in space the system menu bar clips when full —
// the same overflow behavior Ice's real hide relies on, not a drawn cover.
public enum IceBoundary {
    // Where to drag an item so it lands just left of (hide) or right of
    // (reveal) the anchor, clearing the anchor's own width.
    public static func dragTarget(anchorMinX: CGFloat, itemWidth: CGFloat, hiding: Bool) -> CGFloat {
        let margin: CGFloat = 4
        return hiding
            ? anchorMinX - itemWidth / 2 - margin
            : anchorMinX + itemWidth / 2 + margin
    }

    // An item reads as hidden once its center sits at or left of the anchor's
    // leading edge, regardless of which process last moved it there.
    public static func isHidden(itemFrame: CGRect, anchorMinX: CGFloat) -> Bool {
        itemFrame.midX <= anchorMinX
    }
}

// Persisted hidden set, keyed by bundle identifier so it survives relaunches
// (pids are reused, bundle ids aren't).
extension Settings {
    private static let iceHiddenBundleIDsKey = "ice.hiddenBundleIDs"

    public var iceHiddenBundleIDs: Set<String> {
        get { Set((defaultsValue(forKey: Self.iceHiddenBundleIDsKey) as? [String]) ?? []) }
        set { setDefaultsValue(Array(newValue), forKey: Self.iceHiddenBundleIDsKey) }
    }

    public func iceIsHidden(bundleID: String) -> Bool {
        iceHiddenBundleIDs.contains(bundleID)
    }

    public func setIceHidden(_ hidden: Bool, bundleID: String) {
        var set = iceHiddenBundleIDs
        if hidden { set.insert(bundleID) } else { set.remove(bundleID) }
        iceHiddenBundleIDs = set
    }
}
