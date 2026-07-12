import AppKit
import SwiftUI
import FreeSpeechCore

// Floating catcher that appears while the user drags optimizable files
// anywhere on screen, so optimization does not depend on finding (or even
// showing) the menu bar icon. Driven by the module's poll loop: the drag
// pasteboard's changeCount only moves when a drag session starts.
final class ClopDropZoneController {
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
            // Drag pasteboard contents are only readable by drag participants
            // (macOS pasteboard privacy returns empty types to bystanders), so
            // the changeCount bump is the entire signal. A held mouse button
            // separates a real drag gesture from a programmatic pasteboard
            // write; the drop target validates actual types on hover, where
            // reading is permitted.
            if NSEvent.pressedMouseButtons != 0 {
                show()
            }
        }
        // Buttons all up means the drag ended (dropped here, elsewhere, or
        // abandoned); there is nothing left to catch.
        if isVisible, NSEvent.pressedMouseButtons == 0 {
            hide()
        }
    }

    func hide() {
        guard isVisible else { return }
        panel?.dsFadeOut()
        isVisible = false
        Log.info("clop: drop zone hidden")
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        // Bottom-center of whichever screen the drag is happening on.
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
        Log.info("clop: drop zone shown")
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 230, height: 110)
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
        let target = ClopDropTargetView(frame: NSRect(origin: .zero, size: size))
        target.onDrop = { [weak self] urls in
            self?.hide()
            self?.onDrop?(urls)
        }
        panel.contentView = target
        return panel
    }
}

// The drag destination. Visuals live in a hosted SwiftUI view; drags resolve
// to this container because only it registers for the file type.
private final class ClopDropTargetView: NSView {
    var onDrop: (([URL]) -> Void)?
    private let model = ClopDropZoneVisualModel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        let hosting = NSHostingView(rootView: ClopDropZoneVisual(model: model))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
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
        Log.info("clop: \(urls.count) file(s) dropped on drop zone")
        onDrop?(urls)
        return true
    }

    private func supportedURLs(from info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ClopOptimizer.mediaType(forFileExtension: $0.pathExtension) != nil }
    }
}

private final class ClopDropZoneVisualModel: ObservableObject {
    @Published var targeted = false
}

private struct ClopDropZoneVisual: View {
    @ObservedObject var model: ClopDropZoneVisualModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(model.targeted ? Color.dsAccent : Color.dsMuted)
            Text("Drop to optimize")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsPaper)
            Text("Images, videos, PDFs")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.dsInk1.opacity(0.97)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    model.targeted ? Color.dsAccent : Color.dsLine,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .padding(8)
        .animation(.easeOut(duration: 0.12), value: model.targeted)
    }
}
