import AppKit
import SwiftUI
import FreeSpeechCore

// Floating result readout: every optimization outcome surfaces here for a
// couple of seconds, so "nothing happened" is always distinguishable from
// "left untouched on purpose" without opening a menu. Main thread only.
enum ClopToast {
    private static var panel: NSPanel?
    private static let model = ClopToastModel()
    private static var dismissWork: DispatchWorkItem?

    static func show(_ message: String) {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        model.message = message
        position(panel)
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.dsFadeIn()
        }
        dismissWork?.cancel()
        let work = DispatchWorkItem { panel.dsFadeOut() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 110))
    }

    private static func makePanel() -> NSPanel {
        let size = NSSize(width: 320, height: 44)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: ClopToastView(model: model))
        return panel
    }
}

private final class ClopToastModel: ObservableObject {
    @Published var message = ""
}

private struct ClopToastView: View {
    @ObservedObject var model: ClopToastModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.compress.vertical")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsAccent)
            Text(model.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsPaper)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color.dsInk1.opacity(0.97)))
        .overlay(Capsule().strokeBorder(Color.dsLine, lineWidth: 1))
        .padding(4)
    }
}

// Registered as NSApp.servicesProvider at launch so the "Optimize with Clop"
// right-click service always resolves, and gates the work on the module being
// enabled rather than failing silently.
final class ClopServiceBridge: NSObject {
    private let registry: ModuleRegistry

    init(registry: ModuleRegistry) {
        self.registry = registry
    }

    @objc func optimizeWithClop(_ pasteboard: NSPasteboard, userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        Log.info("clop: service invoked with \(urls.count) file(s)")
        guard let module = registry.module(id: ModuleCatalog.clop.id) as? ClopModule,
              registry.isEnabled(id: ModuleCatalog.clop.id) else {
            ClopToast.show("Turn on Clop in FreeKit to optimize files")
            return
        }
        guard !urls.isEmpty else { return }
        module.optimizeFiles(urls)
    }
}
