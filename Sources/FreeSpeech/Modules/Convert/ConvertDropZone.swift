import AppKit
import SwiftUI
import FreeSpeechCore

// Floating catcher that appears while the user drags a convertible file
// anywhere on screen, mirroring Clop's drop zone. Unlike Clop's two-half
// zone (keep vs. convert), there is only one target here: dropping always
// applies whatever format the user has configured per media kind in
// Settings, so a single panel is enough.
final class ConvertDropZoneController {
    var onDrop: (([URL]) -> Void)?
    private var panel: NSPanel?
    private var lastDragChangeCount: Int
    private(set) var isVisible = false

    init() {
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
    }

    func tick() {
        let dragPasteboard = NSPasteboard(name: .drag)
        if dragPasteboard.changeCount != lastDragChangeCount {
            lastDragChangeCount = dragPasteboard.changeCount
            if NSEvent.pressedMouseButtons != 0 {
                show()
            }
        }
        if isVisible, NSEvent.pressedMouseButtons == 0 {
            hide()
        }
    }

    func hide() {
        guard isVisible else { return }
        panel?.dsFadeOut()
        isVisible = false
        Log.info("convert: drop zone hidden")
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 48))
        }
        panel.dsFadeIn()
        isVisible = true
        Log.info("convert: drop zone shown")
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 200, height: 118)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)

        let target = ConvertDropTargetView(frame: NSRect(origin: .zero, size: size))
        target.autoresizingMask = [.width, .height]
        target.onDrop = { [weak self] urls in
            self?.hide()
            self?.onDrop?(urls)
        }
        panel.contentView = target
        return panel
    }
}

private final class ConvertDropTargetView: NSView {
    var onDrop: (([URL]) -> Void)?
    private let model = ConvertDropZoneVisualModel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        let hosting = NSHostingView(rootView: ConvertDropZoneVisual(model: model))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unused: the drop zone is built in code")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = !supportedURLs(from: sender).isEmpty
        model.targeted = accepts
        return accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.targeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.targeted = false
        let urls = supportedURLs(from: sender)
        guard !urls.isEmpty else { return false }
        Log.info("convert: \(urls.count) file(s) dropped on drop zone")
        onDrop?(urls)
        return true
    }

    private func supportedURLs(from info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ConvertPlan.mediaKind(forFileExtension: $0.pathExtension) != nil }
    }
}

private final class ConvertDropZoneVisualModel: ObservableObject {
    @Published var targeted = false
}

private struct ConvertDropZoneVisual: View {
    @ObservedObject var model: ConvertDropZoneVisualModel

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(model.targeted ? Color.dsAccent : Color.dsMuted)
            Text("Convert")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsPaper)
            Text("Uses your configured formats")
                .font(.system(size: 10))
                .foregroundStyle(Color.dsFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.dsInk1.opacity(0.97)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    model.targeted ? Color.dsAccent : Color.dsLine,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .padding(6)
        .animation(DS.animBase, value: model.targeted)
    }
}
