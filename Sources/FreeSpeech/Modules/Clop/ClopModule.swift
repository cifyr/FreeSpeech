import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FreeSpeechCore

// Clop: on-device clipboard/file compressor. Decision rules (watch gate,
// keep-if-smaller, sizing, naming) live in Core's ClopPlan; this layer polls
// the pasteboard, runs the encoders, and swaps results in.
final class ClopModule: NSObject, AppModule, NSMenuDelegate {
    let info = ModuleCatalog.clop

    private let settings: Settings
    private let hub: EventTapHub

    private var hotkeyToken: EventTapHub.HotkeyToken?
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var active = false
    // Pause is runtime-only; a relaunch resumes watching like the card toggle.
    private var watching = true
    private var working = 0
    private var videoProgress: Double?
    private var lastSeenChangeCount = 0
    // changeCount of our own last pasteboard write; the Core gate dedupes on it
    // so the watcher never re-processes its own output.
    private var lastOwnChangeCount = -1
    private var lastResult: String?
    private var lastUndo: UndoAction?
    // Cancellable long-running work (video exports, file batches). Image and
    // PDF encodes finish in well under a second and are not worth cancelling.
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var batchProgress: (done: Int, total: Int)?
    private let paneModel = ClopPaneModel()
    private lazy var settingsWindow = ModuleSettingsWindowController(
        info: info,
        contentSize: NSSize(width: 640, height: 760),
        minimumSize: NSSize(width: 560, height: 480)
    ) { [weak self] in
        self?.makeSettingsPane() ?? AnyView(EmptyView())
    }

    enum Key {
        static let images = "images"
        static let videos = "videos"
        static let pdfs = "pdfs"
        static let quality = "quality"
        static let maxDimension = "maxDimension"  // 0 = no downscale
        static let format = "format"
        static let minSavings = "minSavings"      // fraction, not percent
        static let skipBelowKB = "skipBelowKB"
        static let destination = "destination"
        static let videoPreset = "videoPreset"
        static let totalSavedBytes = "totalSavedBytes"
        static let totalItems = "totalItems"
    }

    private enum UndoAction {
        case clipboard(PasteboardSnapshot)
        case file(original: URL, backup: URL)
    }

    init(settings: Settings, hub: EventTapHub) {
        self.settings = settings
        self.hub = hub
        super.init()
    }

    private var hotkey: HotkeyPreset {
        settings.moduleHotkey(id: info.id, defaultPreset: .disabled)
    }

    static func currentPlan(settings: Settings) -> ClopPlan {
        let id = ModuleCatalog.clop.id
        let maxDimension = settings.moduleInt(id: id, key: Key.maxDimension) ?? 0
        return ClopPlan(
            imagesEnabled: settings.moduleBool(id: id, key: Key.images) ?? true,
            videosEnabled: settings.moduleBool(id: id, key: Key.videos) ?? false,
            pdfsEnabled: settings.moduleBool(id: id, key: Key.pdfs) ?? false,
            quality: settings.moduleDouble(id: id, key: Key.quality) ?? 0.75,
            maxDimension: maxDimension > 0 ? maxDimension : nil,
            // JPEG default: HEIC is smaller, but JPEG pastes into everything.
            outputFormat: settings.moduleString(id: id, key: Key.format)
                .flatMap(ClopPlan.OutputFormat.init) ?? .jpeg,
            minimumSavings: settings.moduleDouble(id: id, key: Key.minSavings) ?? 0.10,
            skipBelowBytes: (settings.moduleInt(id: id, key: Key.skipBelowKB) ?? 10) * 1024,
            fileDestination: settings.moduleString(id: id, key: Key.destination)
                .flatMap(ClopPlan.FileDestination.init) ?? .alongside)
    }

    private var videoPreset: ClopVideoPreset {
        settings.moduleString(id: info.id, key: Key.videoPreset)
            .flatMap(ClopVideoPreset.init) ?? .hd1080
    }

    static var backupsDirectory: URL {
        AppPaths.appSupport.appendingPathComponent("clop-backups", isDirectory: true)
    }

    // MARK: - AppModule

    func activate() {
        active = true
        watching = true
        if hotkeyToken == nil {
            hotkeyToken = hub.register(preset: hotkey, label: "clop.optimizeClipboard") { [weak self] direction in
                if case .down = direction { self?.optimizeClipboardNow() }
            }
        }
        paneModel.module = self
        startPollingIfNeeded()
        Log.info("clop: activated, watching clipboard")
    }

    func deactivate() {
        active = false
        stopPolling()
        cancelAllWork()
        if let hotkeyToken { hub.unregister(hotkeyToken) }
        hotkeyToken = nil
        Log.info("clop: deactivated")
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.toolTip = "Clop compressor \u{2014} drop files here to optimize"
                if let button = item.button {
                    let drop = ClopDropView(frame: button.bounds)
                    drop.autoresizingMask = [.width, .height]
                    drop.onDrop = { [weak self] urls in
                        Log.info("clop: \(urls.count) file(s) dropped on menu bar item")
                        self?.optimizeFiles(urls)
                    }
                    button.addSubview(drop)
                }
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                statusItem = item
                updateStatusIcon()
            }
            statusItem?.isVisible = true
        } else {
            statusItem?.isVisible = false
        }
    }

    func openSettings() {
        settingsWindow.show()
    }

    func makeSettingsPane() -> AnyView {
        paneModel.module = self
        return AnyView(ClopSettingsPane(model: paneModel, settings: settings))
    }

    func updateHotkey(_ preset: HotkeyPreset) {
        settings.setModuleHotkey(preset, id: info.id)
        if let hotkeyToken { hub.update(hotkeyToken, preset: preset) }
    }

    // MARK: - Clipboard watcher

    private func startPollingIfNeeded() {
        guard active, watching, pollTimer == nil else { return }
        // Only fresh copies are fair game: whatever was already on the
        // clipboard when watching started stays untouched.
        lastSeenChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        // Coalescing latitude for the power manager; sub-100ms jitter is
        // invisible next to the 0.5s poll interval.
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func setWatching(_ on: Bool) {
        watching = on
        if on { startPollingIfNeeded() } else { stopPolling() }
        Log.info("clop: watching \(on ? "resumed" : "paused")")
        updateStatusIcon()
    }

    private func poll() {
        guard active, watching else { return }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = changeCount
        handleClipboardChange(pasteboard, changeCount: changeCount, explicit: false)
    }

    func optimizeClipboardNow() {
        // Explicit request: the watch toggles and size floor do not apply, but
        // keep-if-smaller always does.
        let pasteboard = NSPasteboard.general
        Log.info("clop: optimize clipboard now requested (changeCount \(pasteboard.changeCount))")
        handleClipboardChange(pasteboard, changeCount: pasteboard.changeCount, explicit: true)
    }

    private func handleClipboardChange(_ pasteboard: NSPasteboard, changeCount: Int,
                                       explicit: Bool) {
        let types = pasteboard.types ?? []
        // Password managers mark secret payloads concealed; never touch those.
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) {
            Log.info("clop: skipped concealed pasteboard payload")
            return
        }
        guard let candidate = classify(pasteboard) else {
            if explicit { finish(result: "Nothing optimizable on the clipboard") }
            return
        }
        let plan = Self.currentPlan(settings: settings)
        if !explicit {
            switch plan.shouldProcess(type: candidate.mediaType, byteCount: candidate.byteCount,
                                      isOwnWrite: changeCount == lastOwnChangeCount) {
            case .skip(let reason):
                Log.info("clop: skipped \(candidate.mediaType.rawValue) \(candidate.name) (\(candidate.byteCount) bytes): \(reason.rawValue)")
                return
            case .process:
                break
            }
        }
        Log.info("clop: processing \(candidate.mediaType.rawValue) \(candidate.name) (\(candidate.byteCount) bytes, explicit=\(explicit))")
        optimize(candidate, plan: plan, pasteboard: pasteboard, changeCount: changeCount)
    }

    private struct ClipboardCandidate {
        enum Payload {
            case data(Data, UTType)
            case file(URL)
        }
        let payload: Payload
        let mediaType: ClopPlan.MediaType
        let byteCount: Int
        let name: String
    }

    private func classify(_ pasteboard: NSPasteboard) -> ClipboardCandidate? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            // Multi-file copies stay untouched: collapsing them into one
            // optimized payload would drop the other files.
            guard urls.count == 1, let url = urls.first,
                  let mediaType = ClopOptimizer.mediaType(forFileExtension: url.pathExtension)
            else { return nil }
            return ClipboardCandidate(payload: .file(url), mediaType: mediaType,
                                      byteCount: fileSize(url), name: url.lastPathComponent)
        }
        let imageTypes: [(NSPasteboard.PasteboardType, UTType)] = [
            (.png, .png),
            (NSPasteboard.PasteboardType("public.jpeg"), .jpeg),
            (NSPasteboard.PasteboardType("public.heic"), .heic),
            (.tiff, .tiff),
        ]
        for (pbType, utType) in imageTypes {
            if let data = pasteboard.data(forType: pbType) {
                return ClipboardCandidate(payload: .data(data, utType), mediaType: .image,
                                          byteCount: data.count, name: "clipboard image")
            }
        }
        if let data = pasteboard.data(forType: .pdf) {
            return ClipboardCandidate(payload: .data(data, .pdf), mediaType: .pdf,
                                      byteCount: data.count, name: "clipboard PDF")
        }
        return nil
    }

    private func optimize(_ candidate: ClipboardCandidate, plan: ClopPlan,
                          pasteboard: NSPasteboard, changeCount: Int) {
        // File payloads are read inside the background encode block so a large
        // file on a slow (or still-downloading iCloud) volume never stalls the
        // main thread.
        switch (candidate.payload, candidate.mediaType) {
        case (.data(let data, let type), .image):
            optimizeImageForClipboard(load: { data }, sourceType: type,
                                      originalBytes: candidate.byteCount,
                                      plan: plan, pasteboard: pasteboard, changeCount: changeCount)
        case (.file(let url), .image):
            optimizeImageForClipboard(load: { try Data(contentsOf: url) }, sourceType: nil,
                                      originalBytes: candidate.byteCount,
                                      plan: plan, pasteboard: pasteboard, changeCount: changeCount)
        case (.data(let data, _), .pdf):
            optimizePDFForClipboard(load: { data }, originalBytes: candidate.byteCount,
                                    plan: plan, pasteboard: pasteboard, changeCount: changeCount)
        case (.file(let url), .pdf):
            optimizePDFForClipboard(load: { try Data(contentsOf: url) },
                                    originalBytes: candidate.byteCount,
                                    plan: plan, pasteboard: pasteboard, changeCount: changeCount)
        case (.file(let url), .video):
            optimizeVideoForClipboard(url: url, originalBytes: candidate.byteCount,
                                      plan: plan, pasteboard: pasteboard, changeCount: changeCount)
        case (.data, .video):
            // Raw video bytes on the pasteboard have no real producer; ignore.
            break
        }
    }

    private func optimizeImageForClipboard(load: @escaping () throws -> Data,
                                           sourceType: UTType?, originalBytes: Int,
                                           plan: ClopPlan, pasteboard: NSPasteboard,
                                           changeCount: Int) {
        beginWork()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try ClopOptimizer.optimizeImage(load(), plan: plan, sourceHint: sourceType) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.endWork()
                switch outcome {
                case .failure(let error):
                    Log.error("clop: image optimization failed: \(error.localizedDescription)")
                    self.finish(result: "Could not optimize image")
                case .success(let result):
                    Log.info("clop: image encoded \(result.pixelWidth)x\(result.pixelHeight) as \(result.type.identifier), \(originalBytes) -> \(result.data.count) bytes")
                    self.applyClipboardData(result.data, type: result.type,
                                            originalBytes: originalBytes, plan: plan,
                                            pasteboard: pasteboard, changeCount: changeCount)
                }
            }
        }
    }

    private func optimizePDFForClipboard(load: @escaping () throws -> Data, originalBytes: Int,
                                         plan: ClopPlan,
                                         pasteboard: NSPasteboard, changeCount: Int) {
        beginWork()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try ClopOptimizer.optimizePDF(load()) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.endWork()
                switch outcome {
                case .failure(let error):
                    Log.error("clop: PDF optimization failed: \(error.localizedDescription)")
                    self.finish(result: "Could not optimize PDF")
                case .success(let optimized):
                    Log.info("clop: PDF rewritten, \(originalBytes) -> \(optimized.count) bytes")
                    self.applyClipboardData(optimized, type: .pdf,
                                            originalBytes: originalBytes, plan: plan,
                                            pasteboard: pasteboard, changeCount: changeCount)
                }
            }
        }
    }

    private func optimizeVideoForClipboard(url: URL, originalBytes: Int, plan: ClopPlan,
                                           pasteboard: NSPasteboard, changeCount: Int) {
        beginWork()
        let preset = videoPreset.avPreset
        runTracked { [self] in
            defer { self.endWork() }
            do {
                let outputURL = try await ClopOptimizer.optimizeVideo(
                    at: url, preset: preset,
                    outputURL: ClopOptimizer.clipboardVideoOutputURL(for: url)) { [weak self] fraction in
                    self?.videoProgress = fraction
                    self?.updateStatusIcon()
                }
                let optimizedBytes = self.fileSize(outputURL)
                guard pasteboard.changeCount == changeCount else {
                    Log.info("clop: clipboard changed during video export, result discarded")
                    try? FileManager.default.removeItem(at: outputURL)
                    return
                }
                guard plan.keepResult(originalBytes: originalBytes, optimizedBytes: optimizedBytes) else {
                    Log.info("clop: video not smaller (\(originalBytes) -> \(optimizedBytes) bytes), clipboard untouched")
                    try? FileManager.default.removeItem(at: outputURL)
                    self.finish(result: "Already small \u{2014} clipboard left untouched")
                    return
                }
                let snapshot = PasteboardSnapshot(pasteboard)
                pasteboard.clearContents()
                pasteboard.writeObjects([outputURL as NSURL])
                self.rememberOwnWrite(pasteboard)
                self.lastUndo = .clipboard(snapshot)
                self.recordSavings(originalBytes: originalBytes, optimizedBytes: optimizedBytes, items: 1)
                let summary = ClopPlan.savingsSummary(originalBytes: originalBytes, optimizedBytes: optimizedBytes)
                Log.info("clop: clipboard video optimized, \(summary)")
                self.finish(result: summary)
            } catch is CancellationError {
                Log.info("clop: clipboard video optimization cancelled")
                self.finish(result: "Optimization cancelled")
            } catch {
                Log.error("clop: video optimization failed for \(url.lastPathComponent): \(error.localizedDescription)")
                self.finish(result: "Could not optimize \(url.lastPathComponent)")
            }
        }
    }

    private func applyClipboardData(_ data: Data, type: UTType, originalBytes: Int,
                                    plan: ClopPlan, pasteboard: NSPasteboard, changeCount: Int) {
        // The user copied something newer while we were encoding; clobbering
        // that copy would lose it.
        guard pasteboard.changeCount == changeCount else {
            Log.info("clop: clipboard changed during optimization, result discarded")
            return
        }
        guard plan.keepResult(originalBytes: originalBytes, optimizedBytes: data.count) else {
            Log.info("clop: result not smaller (\(originalBytes) -> \(data.count) bytes), clipboard untouched")
            finish(result: "Already small \u{2014} clipboard left untouched")
            return
        }
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        rememberOwnWrite(pasteboard)
        lastUndo = .clipboard(snapshot)
        recordSavings(originalBytes: originalBytes, optimizedBytes: data.count, items: 1)
        let summary = ClopPlan.savingsSummary(originalBytes: originalBytes, optimizedBytes: data.count)
        Log.info("clop: clipboard optimized, \(summary)")
        finish(result: summary)
    }

    private func rememberOwnWrite(_ pasteboard: NSPasteboard) {
        lastOwnChangeCount = pasteboard.changeCount
        lastSeenChangeCount = lastOwnChangeCount
    }

    // MARK: - Undo

    func undoLastOptimization() {
        guard let undo = lastUndo else { return }
        lastUndo = nil
        switch undo {
        case .clipboard(let snapshot):
            let pasteboard = NSPasteboard.general
            snapshot.restore(to: pasteboard)
            rememberOwnWrite(pasteboard)
            Log.info("clop: clipboard restored from pre-optimization snapshot")
            finish(result: "Restored previous clipboard")
        case .file(let original, let backup):
            do {
                // Restore via a staging copy so the backup survives as a second
                // safety net even after a successful undo.
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clop-undo-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: backup, to: staging)
                _ = try FileManager.default.replaceItemAt(original, withItemAt: staging)
                Log.info("clop: restored \(original.path) from backup \(backup.path)")
                finish(result: "Restored \(original.lastPathComponent)")
            } catch {
                Log.error("clop: undo failed for \(original.path) from \(backup.path): \(error.localizedDescription)")
                finish(result: "Undo failed \u{2014} backup kept in clop-backups")
            }
        }
    }

    // MARK: - File optimization

    func optimizeFilesFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .movie, .pdf]
        panel.message = "Choose images, videos, or PDFs to optimize"
        panel.prompt = "Optimize"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let self, !panel.urls.isEmpty else { return }
            self.optimizeFiles(panel.urls)
        }
    }

    private func optimizeFiles(_ urls: [URL]) {
        let plan = Self.currentPlan(settings: settings)
        let preset = videoPreset.avPreset
        Log.info("clop: optimizing \(urls.count) file(s), destination=\(plan.fileDestination.rawValue)")
        runTracked { [self] in
            beginWork()
            var optimizedCount = 0
            var skipped = 0
            var cancelled = false
            var totalOriginal = 0
            var totalOptimized = 0
            for (index, url) in urls.enumerated() {
                if Task.isCancelled {
                    skipped += urls.count - index
                    cancelled = true
                    Log.info("clop: batch cancelled after \(index) of \(urls.count) file(s)")
                    break
                }
                batchProgress = (index, urls.count)
                updateStatusIcon()
                do {
                    if let sizes = try await optimizeFile(url, plan: plan, preset: preset) {
                        optimizedCount += 1
                        totalOriginal += sizes.original
                        totalOptimized += sizes.optimized
                    } else {
                        skipped += 1
                    }
                } catch is CancellationError {
                    skipped += urls.count - index
                    cancelled = true
                    Log.info("clop: batch cancelled during \(url.lastPathComponent)")
                    break
                } catch {
                    skipped += 1
                    Log.error("clop: file optimization failed for \(url.path): \(error.localizedDescription)")
                }
            }
            endWork()
            if optimizedCount > 0 {
                recordSavings(originalBytes: totalOriginal, optimizedBytes: totalOptimized,
                              items: optimizedCount)
            }
            let summary: String
            if cancelled {
                summary = "Cancelled \u{2014} \(optimizedCount) file\(optimizedCount == 1 ? "" : "s") done first"
            } else if optimizedCount > 0 {
                let counts = "\(optimizedCount) file\(optimizedCount == 1 ? "" : "s")"
                    + (skipped > 0 ? ", \(skipped) skipped" : "")
                summary = "\(ClopPlan.savingsSummary(originalBytes: totalOriginal, optimizedBytes: totalOptimized)) \u{2014} \(counts)"
            } else {
                summary = "No files shrank \u{2014} originals untouched"
            }
            Log.info("clop: file run done \u{2014} \(optimizedCount) optimized, \(skipped) skipped")
            finish(result: summary)
        }
    }

    // Returns nil when the file was skipped (unsupported or not smaller).
    // Explicitly picked files bypass the watch toggles and size floor; the
    // keep-if-smaller rule still applies to every one of them.
    private func optimizeFile(_ url: URL, plan: ClopPlan,
                              preset: String) async throws -> (original: Int, optimized: Int)? {
        guard let mediaType = ClopOptimizer.mediaType(forFileExtension: url.pathExtension) else {
            Log.info("clop: skipped \(url.lastPathComponent): unsupported type")
            return nil
        }
        let originalBytes = fileSize(url)
        switch mediaType {
        case .image:
            // Replacing in place must not silently change a file's format, so
            // replace runs always keep the original encoding.
            var filePlan = plan
            if plan.fileDestination == .replace { filePlan.outputFormat = .keep }
            let encodePlan = filePlan
            let result = try await Task.detached(priority: .userInitiated) {
                try ClopOptimizer.optimizeImage(Data(contentsOf: url), plan: encodePlan)
            }.value
            guard plan.keepResult(originalBytes: originalBytes, optimizedBytes: result.data.count) else {
                Log.info("clop: \(url.lastPathComponent) not smaller (\(originalBytes) -> \(result.data.count) bytes), skipped")
                return nil
            }
            let ext = result.type.preferredFilenameExtension ?? url.pathExtension
            try writeFileResult(data: result.data, for: url, plan: plan, preferredExtension: ext)
            return (originalBytes, result.data.count)
        case .pdf:
            let optimized = try await Task.detached(priority: .userInitiated) {
                try ClopOptimizer.optimizePDF(Data(contentsOf: url))
            }.value
            guard plan.keepResult(originalBytes: originalBytes, optimizedBytes: optimized.count) else {
                Log.info("clop: \(url.lastPathComponent) not smaller (\(originalBytes) -> \(optimized.count) bytes), skipped")
                return nil
            }
            try writeFileResult(data: optimized, for: url, plan: plan, preferredExtension: "pdf")
            return (originalBytes, optimized.count)
        case .video:
            let outputURL = try await ClopOptimizer.optimizeVideo(
                at: url, preset: preset,
                outputURL: ClopOptimizer.batchVideoOutputURL()) { [weak self] fraction in
                self?.videoProgress = fraction
                self?.updateStatusIcon()
            }
            let optimizedBytes = fileSize(outputURL)
            guard plan.keepResult(originalBytes: originalBytes, optimizedBytes: optimizedBytes) else {
                Log.info("clop: \(url.lastPathComponent) not smaller (\(originalBytes) -> \(optimizedBytes) bytes), skipped")
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }
            try moveFileResult(from: outputURL, for: url, plan: plan)
            return (originalBytes, optimizedBytes)
        }
    }

    private func writeFileResult(data: Data, for original: URL, plan: ClopPlan,
                                 preferredExtension: String) throws {
        switch plan.fileDestination {
        case .alongside:
            let sibling = ClopPlan.siblingURL(for: original, preferredExtension: preferredExtension) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            try data.write(to: sibling, options: .atomic)
            Log.info("clop: wrote \(sibling.path)")
        case .replace:
            let backup = try backUp(original)
            // .atomic writes to a temp file and renames, so a crash mid-write
            // can never leave a truncated original.
            try data.write(to: original, options: .atomic)
            lastUndo = .file(original: original, backup: backup)
            Log.info("clop: replaced \(original.path), backup at \(backup.path)")
        }
    }

    private func moveFileResult(from temp: URL, for original: URL, plan: ClopPlan) throws {
        switch plan.fileDestination {
        case .alongside:
            let sibling = ClopPlan.siblingURL(for: original, preferredExtension: "mp4") {
                FileManager.default.fileExists(atPath: $0.path)
            }
            try FileManager.default.moveItem(at: temp, to: sibling)
            Log.info("clop: wrote \(sibling.path)")
        case .replace:
            // The path (and any .mov extension) is preserved even though the
            // container is now mp4: renaming would break references, and mp4
            // data under a .mov name still plays. The backup keeps the true original.
            let backup = try backUp(original)
            _ = try FileManager.default.replaceItemAt(original, withItemAt: temp)
            lastUndo = .file(original: original, backup: backup)
            Log.info("clop: replaced \(original.path), backup at \(backup.path)")
        }
    }

    private func backUp(_ url: URL) throws -> URL {
        let directory = Self.backupsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = ClopPlan.backupURL(for: url, in: directory) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    }

    func revealBackupsFolder() {
        let directory = Self.backupsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
        Log.info("clop: opened backups folder \(directory.path)")
    }

    // MARK: - Work tracking

    private func runTracked(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        runningTasks[id] = Task { @MainActor in
            await operation()
            runningTasks[id] = nil
        }
    }

    func cancelAllWork() {
        guard !runningTasks.isEmpty else { return }
        Log.info("clop: cancelling \(runningTasks.count) running task(s)")
        for task in runningTasks.values { task.cancel() }
    }

    // Lifetime savings counter persists in Settings so it survives relaunches.
    private func recordSavings(originalBytes: Int, optimizedBytes: Int, items: Int) {
        let saved = max(0, originalBytes - optimizedBytes)
        let total = (settings.moduleInt(id: info.id, key: Key.totalSavedBytes) ?? 0) + saved
        let count = (settings.moduleInt(id: info.id, key: Key.totalItems) ?? 0) + items
        settings.setModuleInt(total, id: info.id, key: Key.totalSavedBytes)
        settings.setModuleInt(count, id: info.id, key: Key.totalItems)
    }

    // MARK: - Status item

    private func beginWork() {
        working += 1
        updateStatusIcon()
    }

    private func endWork() {
        working = max(0, working - 1)
        if working == 0 {
            videoProgress = nil
            batchProgress = nil
        }
        updateStatusIcon()
    }

    private func finish(result: String) {
        lastResult = result
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let paused = working == 0 && !watching
        button.image = NSImage(
            systemSymbolName: paused ? "pause.rectangle" : "rectangle.compress.vertical",
            accessibilityDescription: working > 0 ? "Clop optimizing"
                : (paused ? "Clop paused" : "Clop watching clipboard"))
        // Accent tint = live activity, matching the suite's use of red for "hot".
        button.contentTintColor = working > 0 ? DS.accent : nil
        button.appearsDisabled = paused
        let progressText: String
        if working > 0, let batch = batchProgress {
            progressText = " \(batch.done + 1)/\(batch.total)"
        } else if working > 0, let videoProgress {
            progressText = String(format: " %.0f%%", videoProgress * 100)
        } else {
            progressText = ""
        }
        button.attributedTitle = NSAttributedString(
            string: progressText,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        button.toolTip = working > 0 ? "Clop: optimizing"
            : (paused ? "Clop: paused" : "Clop: watching clipboard")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let statusTitle: String
        if working > 0, let batch = batchProgress {
            statusTitle = "Optimizing \(batch.done + 1) of \(batch.total)\u{2026}"
        } else if working > 0 {
            statusTitle = videoProgress.map { String(format: "Optimizing video \u{2014} %.0f%%", $0 * 100) }
                ?? "Optimizing\u{2026}"
        } else {
            statusTitle = watching ? "Watching clipboard" : "Watching paused"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let lastResult {
            let last = NSMenuItem(title: lastResult, action: nil, keyEquivalent: "")
            last.isEnabled = false
            menu.addItem(last)
        }
        let totalSaved = settings.moduleInt(id: info.id, key: Key.totalSavedBytes) ?? 0
        if totalSaved > 0 {
            let total = NSMenuItem(
                title: ClopPlan.totalSummary(
                    savedBytes: totalSaved,
                    items: settings.moduleInt(id: info.id, key: Key.totalItems) ?? 0),
                action: nil, keyEquivalent: "")
            total.isEnabled = false
            menu.addItem(total)
        }
        menu.addItem(.separator())
        if working > 0 {
            let cancel = NSMenuItem(
                title: "Cancel Optimization", action: #selector(menuCancelWork), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }
        let pause = NSMenuItem(
            title: watching ? "Pause Watching" : "Resume Watching",
            action: #selector(menuTogglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let hotkeySuffix = hotkey.keyCode == HotkeyPreset.disabled.keyCode
            ? "" : " (\(hotkey.displayName))"
        let now = NSMenuItem(
            title: "Optimize Clipboard Now\(hotkeySuffix)",
            action: #selector(menuOptimizeClipboard), keyEquivalent: "")
        now.target = self
        menu.addItem(now)
        let files = NSMenuItem(
            title: "Optimize Files\u{2026}", action: #selector(menuOptimizeFiles), keyEquivalent: "")
        files.target = self
        menu.addItem(files)
        let undo = NSMenuItem(
            title: "Undo Last Optimization", action: #selector(menuUndo), keyEquivalent: "")
        undo.target = self
        undo.isEnabled = lastUndo != nil
        menu.addItem(undo)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Clop Settings\u{2026}", action: #selector(menuOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
    }

    @objc private func menuTogglePause() {
        setWatching(!watching)
    }

    @objc private func menuOptimizeClipboard() {
        optimizeClipboardNow()
    }

    @objc private func menuOptimizeFiles() {
        optimizeFilesFromPanel()
    }

    @objc private func menuUndo() {
        undoLastOptimization()
    }

    @objc private func menuCancelWork() {
        cancelAllWork()
    }

    @objc private func menuOpenSettings() {
        openSettings()
    }
}

// Transparent overlay on the status-item button that accepts file drags.
// hitTest returns nil so clicks fall through to the button and its menu; drag
// destination lookup goes by registered types, not hitTest, so drops still land.
private final class ClopDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        supportedURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = supportedURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func supportedURLs(from info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ClopOptimizer.mediaType(forFileExtension: $0.pathExtension) != nil }
    }
}

// Full multi-item, multi-type capture of the pasteboard so Undo restores
// exactly what was there, not just the representation we happened to optimize.
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var byType = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) { byType[type] = data }
            }
            return byType
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { byType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in byType { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

// MARK: - Settings pane

// Bridges the module to SwiftUI so the hotkey recorder can reach it.
final class ClopPaneModel: ObservableObject {
    weak var module: ClopModule?
}

private struct ClopSettingsPane: View {
    @ObservedObject var model: ClopPaneModel
    let settings: Settings

    private let moduleID = ModuleCatalog.clop.id
    @State private var watchImages: Bool
    @State private var watchVideos: Bool
    @State private var watchPDFs: Bool
    @State private var quality: Double
    @State private var maxDimension: Double
    @State private var format: ClopPlan.OutputFormat
    @State private var videoPreset: ClopVideoPreset
    @State private var minSavingsPercent: Double
    @State private var skipBelowKB: Double
    @State private var destination: ClopPlan.FileDestination

    init(model: ClopPaneModel, settings: Settings) {
        self.model = model
        self.settings = settings
        let id = ModuleCatalog.clop.id
        _watchImages = State(initialValue: settings.moduleBool(id: id, key: ClopModule.Key.images) ?? true)
        _watchVideos = State(initialValue: settings.moduleBool(id: id, key: ClopModule.Key.videos) ?? false)
        _watchPDFs = State(initialValue: settings.moduleBool(id: id, key: ClopModule.Key.pdfs) ?? false)
        _quality = State(initialValue: settings.moduleDouble(id: id, key: ClopModule.Key.quality) ?? 0.75)
        _maxDimension = State(initialValue: Double(settings.moduleInt(id: id, key: ClopModule.Key.maxDimension) ?? 0))
        _format = State(initialValue: settings.moduleString(id: id, key: ClopModule.Key.format)
            .flatMap(ClopPlan.OutputFormat.init) ?? .jpeg)
        _videoPreset = State(initialValue: settings.moduleString(id: id, key: ClopModule.Key.videoPreset)
            .flatMap(ClopVideoPreset.init) ?? .hd1080)
        _minSavingsPercent = State(initialValue: (settings.moduleDouble(id: id, key: ClopModule.Key.minSavings) ?? 0.10) * 100)
        _skipBelowKB = State(initialValue: Double(settings.moduleInt(id: id, key: ClopModule.Key.skipBelowKB) ?? 10))
        _destination = State(initialValue: settings.moduleString(id: id, key: ClopModule.Key.destination)
            .flatMap(ClopPlan.FileDestination.init) ?? .alongside)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSettingsCard(title: "Watch clipboard") {
                DSToggleRow(
                    title: "Images",
                    caption: "Optimize images the moment they are copied.",
                    isOn: boolBinding($watchImages, key: ClopModule.Key.images))
                DSToggleRow(
                    title: "Videos",
                    caption: "Copied video files re-export in the background; exports can take a while.",
                    isOn: boolBinding($watchVideos, key: ClopModule.Key.videos))
                DSToggleRow(
                    title: "PDFs",
                    caption: "Rewrites copied PDFs with screen-optimized images.",
                    isOn: boolBinding($watchPDFs, key: ClopModule.Key.pdfs))
                Text("Copies marked concealed (password managers) are always left alone. Per-app exclusions may come later.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
            }

            DSSettingsCard(title: "Images") {
                optionRow("Quality") {
                    ForEach([(0.5, "Small"), (0.75, "Balanced"), (0.9, "High")], id: \.0) { value, title in
                        chip(title, selected: abs(quality - value) < 0.0001) {
                            quality = value
                            settings.setModuleDouble(value, id: moduleID, key: ClopModule.Key.quality)
                        }
                    }
                    DSNumberField(
                        placeholder: "0\u{2013}1", value: $quality,
                        range: ClopPlan.qualityRange, fractionDigits: 2,
                        onCommit: { settings.setModuleDouble($0, id: moduleID, key: ClopModule.Key.quality) })
                }
                optionRow("Max size") {
                    ForEach([0, 1440, 2160, 3840], id: \.self) { value in
                        chip(value == 0 ? "Off" : "\(value)", selected: Int(maxDimension) == value) {
                            setMaxDimension(Double(value))
                        }
                    }
                    DSNumberField(
                        placeholder: "px", value: $maxDimension,
                        range: 0...10_000, fractionDigits: 0,
                        onCommit: { setMaxDimension($0) })
                    Text("px")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
                optionRow("Format") {
                    ForEach(ClopPlan.OutputFormat.allCases, id: \.rawValue) { value in
                        chip(value.displayName, selected: format == value) {
                            format = value
                            settings.setModuleString(value.rawValue, id: moduleID, key: ClopModule.Key.format)
                        }
                    }
                }
                Text("JPEG pastes everywhere; HEIC is smaller but some apps reject it. Transparent images keep their own format so JPEG never mattes them onto a solid background. Replace-in-place file runs always keep the original format.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
            }

            DSSettingsCard(title: "Videos") {
                optionRow("Preset") {
                    ForEach(ClopVideoPreset.allCases, id: \.rawValue) { value in
                        chip(value.displayName, selected: videoPreset == value) {
                            videoPreset = value
                            settings.setModuleString(value.rawValue, id: moduleID, key: ClopModule.Key.videoPreset)
                        }
                    }
                }
            }

            DSSettingsCard(title: "Rules") {
                optionRow("Min savings") {
                    DSNumberField(
                        placeholder: "%", value: $minSavingsPercent,
                        range: 0...90, fractionDigits: 0,
                        onCommit: { settings.setModuleDouble($0 / 100, id: moduleID, key: ClopModule.Key.minSavings) })
                    Text("% \u{2014} results that shrink less than this leave the original untouched")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
                optionRow("Skip below") {
                    DSNumberField(
                        placeholder: "KB", value: $skipBelowKB,
                        range: 0...100_000, fractionDigits: 0,
                        onCommit: { settings.setModuleInt(Int($0), id: moduleID, key: ClopModule.Key.skipBelowKB) })
                    Text("KB \u{2014} smaller clipboard payloads are not worth touching")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
            }

            DSSettingsCard(title: "Files") {
                optionRow("Output") {
                    ForEach(ClopPlan.FileDestination.allCases, id: \.rawValue) { value in
                        chip(value.displayName, selected: destination == value) {
                            destination = value
                            settings.setModuleString(value.rawValue, id: moduleID, key: ClopModule.Key.destination)
                        }
                    }
                }
                Text("Alongside writes \u{201C}name (clopped)\u{201D} next to the original. Replaced files are backed up first. Files can also be dropped straight onto the menu bar icon.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
                Button("Show Backup Folder") { model.module?.revealBackupsFolder() }
                    .buttonStyle(GhostButtonStyle())
            }

            DSSettingsCard(title: "Control") {
                HotkeyRecorderButton(
                    label: "Optimize clipboard",
                    preset: settings.moduleHotkey(id: moduleID, defaultPreset: .disabled),
                    onChange: { model.module?.updateHotkey($0) })
            }
        }
    }

    private func boolBinding(_ state: Binding<Bool>, key: String) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue },
            set: {
                state.wrappedValue = $0
                settings.setModuleBool($0, id: moduleID, key: key)
            })
    }

    private func setMaxDimension(_ value: Double) {
        maxDimension = value.rounded()
        settings.setModuleInt(Int(maxDimension), id: moduleID, key: ClopModule.Key.maxDimension)
    }

    private func optionRow<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsFaint)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
    }
}

// Compact chip: content-sized, not stretched across the row.
private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    DSChip(title: title, selected: selected, action: action)
        .fixedSize()
}
