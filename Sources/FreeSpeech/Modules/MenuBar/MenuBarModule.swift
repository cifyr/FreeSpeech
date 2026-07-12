import AppKit
import Combine
import SwiftUI
import FreeSpeechCore

extension Notification.Name {
    static let toggleFreeKitMenuShelf = Notification.Name("FreeKit.toggleMenuShelf")
}

enum MenuBarShelfSide: String, CaseIterable, Identifiable {
    case left = "Left"
    case right = "Right"
    var id: String { rawValue }
}

enum MenuBarShelfDensity: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case comfortable = "Comfortable"
    var id: String { rawValue }
}

enum MenuBarShelfPreset: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case balanced = "Balanced"
    case expanded = "Expanded"
    var id: String { rawValue }
}

struct MenuBarIconChoice: Identifiable {
    let symbol: String
    let name: String
    var id: String { symbol }

    static let all: [MenuBarIconChoice] = [
        .init(symbol: "circle.grid.2x2", name: "Grid"),
        .init(symbol: "square.grid.2x2", name: "Tiles"),
        .init(symbol: "slider.horizontal.3", name: "Controls"),
        .init(symbol: "bolt", name: "Bolt"),
        .init(symbol: "sparkles", name: "Spark"),
        .init(symbol: "star", name: "Star"),
        .init(symbol: "circle", name: "Circle"),
        .init(symbol: "diamond", name: "Diamond"),
        .init(symbol: "waveform", name: "Wave"),
        .init(symbol: "command", name: "Command"),
    ]
}

final class MenuBarPreferences: ObservableObject {
    static let shared = MenuBarPreferences()

    private enum Key {
        static let side = "menubar.shelf.side"
        static let width = "menubar.shelf.width"
        static let columns = "menubar.shelf.columns"
        static let showLabels = "menubar.shelf.showLabels"
        static let autoClose = "menubar.shelf.autoClose"
        static let showDisabled = "menubar.shelf.showDisabled"
        static let density = "menubar.shelf.density"
        static let showSearch = "menubar.shelf.showSearch"
        static let favorites = "menubar.shelf.favorites"
        static let icons = "menubar.shelf.icons"
    }

    private let defaults: UserDefaults

    @Published var side: MenuBarShelfSide { didSet { defaults.set(side.rawValue, forKey: Key.side) } }
    @Published var width: Double { didSet { defaults.set(width, forKey: Key.width) } }
    @Published var columns: Int { didSet { defaults.set(columns, forKey: Key.columns) } }
    @Published var showLabels: Bool { didSet { defaults.set(showLabels, forKey: Key.showLabels) } }
    @Published var autoClose: Bool { didSet { defaults.set(autoClose, forKey: Key.autoClose) } }
    @Published var showDisabled: Bool { didSet { defaults.set(showDisabled, forKey: Key.showDisabled) } }
    @Published var density: MenuBarShelfDensity {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }
    @Published var showSearch: Bool { didSet { defaults.set(showSearch, forKey: Key.showSearch) } }
    @Published private(set) var favoriteIDs: Set<String> {
        didSet { defaults.set(Array(favoriteIDs).sorted(), forKey: Key.favorites) }
    }
    @Published private(set) var iconSymbols: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(iconSymbols) {
                defaults.set(data, forKey: Key.icons)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        side = MenuBarShelfSide(rawValue: defaults.string(forKey: Key.side) ?? "") ?? .right
        width = defaults.object(forKey: Key.width) as? Double ?? 360
        columns = defaults.object(forKey: Key.columns) as? Int ?? 4
        showLabels = defaults.object(forKey: Key.showLabels) as? Bool ?? true
        autoClose = defaults.object(forKey: Key.autoClose) as? Bool ?? true
        showDisabled = defaults.object(forKey: Key.showDisabled) as? Bool ?? false
        density = MenuBarShelfDensity(rawValue: defaults.string(forKey: Key.density) ?? "")
            ?? .comfortable
        showSearch = defaults.object(forKey: Key.showSearch) as? Bool ?? true
        favoriteIDs = Set(defaults.stringArray(forKey: Key.favorites) ?? [])
        iconSymbols = defaults.data(forKey: Key.icons)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func symbol(for info: ModuleInfo) -> String {
        iconSymbols[info.id] ?? info.symbolName
    }

    func setSymbol(_ symbol: String, moduleID: String) {
        iconSymbols[moduleID] = symbol
    }

    func resetSymbols() {
        iconSymbols = [:]
    }

    func isFavorite(_ moduleID: String) -> Bool {
        favoriteIDs.contains(moduleID)
    }

    func toggleFavorite(_ moduleID: String) {
        if favoriteIDs.contains(moduleID) { favoriteIDs.remove(moduleID) }
        else { favoriteIDs.insert(moduleID) }
    }

    func apply(_ preset: MenuBarShelfPreset) {
        switch preset {
        case .compact:
            width = 300
            columns = 5
            showLabels = false
            density = .compact
        case .balanced:
            width = 380
            columns = 4
            showLabels = true
            density = .comfortable
        case .expanded:
            width = 500
            columns = 5
            showLabels = true
            density = .comfortable
        }
    }
}

final class MenuBarModule: NSObject, AppModule {
    let info = ModuleCatalog.menuBarManager

    private let registry: ModuleRegistry
    private let preferences = MenuBarPreferences.shared
    private let coordinator = OverlayLayoutCoordinator.shared
    private let onOpenControlCenter: () -> Void
    private var statusItem: NSStatusItem?
    private lazy var shelf = MenuBarShelfController(
        registry: registry,
        preferences: preferences,
        coordinator: coordinator,
        onOpenControlCenter: onOpenControlCenter)
    private lazy var settingsWindow = ModuleSettingsWindowController(
        info: info,
        contentSize: NSSize(width: 600, height: 680),
        minimumSize: NSSize(width: 540, height: 440)
    ) { [registry] in
        AnyView(MenuBarSettingsPane(registry: registry))
    }

    init(registry: ModuleRegistry, onOpenControlCenter: @escaping () -> Void) {
        self.registry = registry
        self.onOpenControlCenter = onOpenControlCenter
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleShelfNotification),
            name: .toggleFreeKitMenuShelf,
            object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func activate() {
        coordinator.setMenuBarActive(true)
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "menubar.rectangle",
                    accessibilityDescription: "FreeKit menu shelf")
                button.toolTip = "FreeKit Menu Bar"
                button.target = self
                button.action = #selector(statusItemClicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
        }
        for delay in [0.0, 0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.publishTriggerFrame()
            }
        }
    }

    func deactivate() {
        shelf.hide()
        statusItem?.isVisible = false
        coordinator.setMenuBarActive(false)
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
        coordinator.setMenuBarActive(visible)
        if visible {
            DispatchQueue.main.async { [weak self] in self?.publishTriggerFrame() }
        }
    }

    var settingsStyle: ModuleSettingsStyle { .window }
    func makeSettingsPane() -> AnyView { AnyView(MenuBarSettingsPane(registry: registry)) }
    func openSettings() { settingsWindow.show() }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            shelf.toggle()
        }
    }

    @objc private func toggleShelfNotification() { shelf.toggle() }

    private func publishTriggerFrame() {
        guard let button = statusItem?.button,
              statusItem?.isVisible == true,
              let window = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        coordinator.updateMenuTrigger(frame: window.convertToScreen(rectInWindow))
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let openShelf = NSMenuItem(title: "Open Shelf", action: #selector(openShelfAction), keyEquivalent: "")
        openShelf.target = self
        menu.addItem(openShelf)
        menu.addItem(.separator())
        for module in registry.modules where module.info.status == .available && module.info.id != info.id {
            let item = NSMenuItem(
                title: module.info.displayName,
                action: #selector(openModuleFromMenu(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = module.info.id
            item.image = NSImage(
                systemSymbolName: preferences.symbol(for: module.info),
                accessibilityDescription: module.info.displayName)
            item.state = registry.isEnabled(id: module.info.id) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Menu Bar Settings\u{2026}", action: #selector(openSettingsAction), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    @objc private func openShelfAction() { shelf.show() }
    @objc private func openSettingsAction() { openSettings() }

    @objc private func openModuleFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let module = registry.module(id: id) else { return }
        if !registry.isEnabled(id: id) {
            registry.setEnabled(true, id: id)
        }
        if module.settingsStyle == .window { module.openSettings() }
        else { onOpenControlCenter() }
    }
}

private final class MenuBarShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class MenuBarShelfController {
    private let panel: MenuBarShelfPanel
    private let registry: ModuleRegistry
    private let preferences: MenuBarPreferences
    private let coordinator: OverlayLayoutCoordinator
    private let onOpenControlCenter: () -> Void
    private var subscriptions: Set<AnyCancellable> = []

    init(
        registry: ModuleRegistry,
        preferences: MenuBarPreferences,
        coordinator: OverlayLayoutCoordinator,
        onOpenControlCenter: @escaping () -> Void
    ) {
        self.registry = registry
        self.preferences = preferences
        self.coordinator = coordinator
        self.onOpenControlCenter = onOpenControlCenter
        panel = MenuBarShelfPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: MenuBarShelfView(
            registry: registry,
            preferences: preferences,
            onOpen: { [weak panel] module in
                if !registry.isEnabled(id: module.info.id) {
                    registry.setEnabled(true, id: module.info.id)
                }
                if module.settingsStyle == .window { module.openSettings() }
                else { onOpenControlCenter() }
                if preferences.autoClose { panel?.orderOut(nil) }
            },
            onOpenControlCenter: onOpenControlCenter))

        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshFrame() }
        }.store(in: &subscriptions)
        coordinator.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshFrame() }
        }.store(in: &subscriptions)
        registry.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshFrame() }
        }.store(in: &subscriptions)
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        refreshFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        coordinator.clearMenuShelf()
    }

    private func refreshFrame() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let count = registry.modules.filter {
            $0.info.status == .available && $0.info.id != ModuleCatalog.menuBarManager.id
                && (preferences.showDisabled || registry.isEnabled(id: $0.info.id))
        }.count
        let columns = max(2, min(6, preferences.columns))
        let rows = max(1, Int(ceil(Double(max(1, count)) / Double(columns))))
        let tileHeight = preferences.density == .compact
            ? (preferences.showLabels ? 54 : 40)
            : (preferences.showLabels ? 68 : 50)
        let searchHeight = preferences.showSearch ? 42 : 0
        let height = CGFloat(64 + searchHeight + rows * tileHeight)
        let width = CGFloat(max(280, min(520, preferences.width)))
        let visible = screen.visibleFrame
        var frame = NSRect(
            x: preferences.side == .left ? visible.minX + 10 : visible.maxX - width - 10,
            y: visible.maxY - height - 8,
            width: width,
            height: height)
        let reserved = coordinator.notchFrame.insetBy(dx: -8, dy: -8)
        if coordinator.notchExpanded, !reserved.isEmpty, frame.intersects(reserved) {
            frame.origin.y = reserved.minY - height - 8
        }
        panel.setFrame(frame, display: panel.isVisible, animate: panel.isVisible)
        if panel.isVisible { coordinator.updateMenuShelf(frame: frame) }
    }
}

private struct MenuBarShelfView: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var preferences: MenuBarPreferences
    let onOpen: (AppModule) -> Void
    let onOpenControlCenter: () -> Void
    @State private var searchText = ""

    private var modules: [AppModule] {
        let available = registry.modules.filter {
            $0.info.status == .available && $0.info.id != ModuleCatalog.menuBarManager.id
                && (preferences.showDisabled || registry.isEnabled(id: $0.info.id))
        }
        let filtered = searchText.isEmpty ? available : available.filter {
            $0.info.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.info.summary.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted {
            let lhsFavorite = preferences.isFavorite($0.info.id)
            let rhsFavorite = preferences.isFavorite($1.info.id)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return $0.info.displayName.localizedCaseInsensitiveCompare($1.info.displayName) == .orderedAscending
        }
    }

    private var tileHeight: CGFloat {
        if preferences.density == .compact { return preferences.showLabels ? 46 : 34 }
        return preferences.showLabels ? 58 : 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FREEKIT SHELF")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .kerning(1.1)
                        .foregroundStyle(Color.dsAccent)
                    Text("Quick Tools")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.dsPaper)
                }
                Spacer()
                Button(action: onOpenControlCenter) {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsMuted)
                .help("Open Control Center")
            }
            if preferences.showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.dsFaint)
                    TextField("Find a FreeKit tool", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsPaper)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.dsFaint)
                        .help("Clear Search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.dsInk2,
                            in: RoundedRectangle(cornerRadius: DS.radiusKeycap, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusKeycap, style: .continuous)
                    .strokeBorder(Color.dsLine, lineWidth: 1))
            }
            if modules.isEmpty {
                Text(searchText.isEmpty
                     ? "Enable a tool in Control Center to add it here."
                     : "No tools match \"\(searchText)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                   count: max(2, min(6, preferences.columns))),
                    spacing: 8
                ) {
                    ForEach(modules, id: \.info.id) { module in
                        Button { onOpen(module) } label: {
                            VStack(spacing: preferences.showLabels ? 6 : 0) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: preferences.symbol(for: module.info))
                                        .font(.system(
                                            size: preferences.density == .compact ? 15 : 17,
                                            weight: .semibold))
                                        .foregroundStyle(
                                            registry.isEnabled(id: module.info.id)
                                                ? Color.dsAccent : Color.dsMuted)
                                        .frame(maxWidth: .infinity)
                                    if preferences.isFavorite(module.info.id) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Color.dsAccent)
                                    }
                                }
                                if preferences.showLabels {
                                    Text(module.info.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.dsPaper)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: tileHeight)
                            .background(Color.dsInk2,
                                        in: RoundedRectangle(cornerRadius: DS.radiusKeycap, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.radiusKeycap, style: .continuous)
                                .strokeBorder(Color.dsLine, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                preferences.toggleFavorite(module.info.id)
                            } label: {
                                Label(
                                    preferences.isFavorite(module.info.id)
                                        ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: preferences.isFavorite(module.info.id)
                                        ? "star.slash" : "star")
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.dsInk0.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard, style: .continuous)
            .strokeBorder(Color.dsLine, lineWidth: 1))
    }
}

struct MenuBarSettingsPane: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject private var preferences = MenuBarPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSettingsCard(title: "Shelf Layout") {
                HStack {
                    Button {
                        NotificationCenter.default.post(name: .toggleFreeKitMenuShelf, object: nil)
                    } label: {
                        Label("Preview Shelf", systemImage: "rectangle.grid.2x2")
                    }
                    .buttonStyle(GhostButtonStyle())
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach(MenuBarShelfPreset.allCases) { preset in
                        Button { preferences.apply(preset) } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                HStack(spacing: 8) {
                    ForEach(MenuBarShelfSide.allCases) { side in
                        DSChip(title: side.rawValue, selected: preferences.side == side) {
                            preferences.side = side
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(MenuBarShelfDensity.allCases) { density in
                        DSChip(title: density.rawValue, selected: preferences.density == density) {
                            preferences.density = density
                        }
                    }
                }
                settingSlider("Width", value: $preferences.width, range: 280...520, suffix: "pt")
                HStack {
                    Text("Columns")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dsPaper)
                    Spacer()
                    Stepper(value: $preferences.columns, in: 2...6) {
                        Text("\(preferences.columns)")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.dsMuted)
                    }
                    .fixedSize()
                }
                DSToggleRow(title: "Show labels", isOn: $preferences.showLabels)
                DSToggleRow(title: "Show search field", isOn: $preferences.showSearch)
                DSToggleRow(title: "Close after opening a tool", isOn: $preferences.autoClose)
                DSToggleRow(title: "Include disabled tools", isOn: $preferences.showDisabled)
            }

            DSSettingsCard(title: "Submenu Icons") {
                ForEach(registry.modules.map(\.info).filter {
                    $0.status == .available && $0.id != ModuleCatalog.menuBarManager.id
                }) { info in
                    HStack(spacing: 12) {
                        Button { preferences.toggleFavorite(info.id) } label: {
                            Image(systemName: preferences.isFavorite(info.id) ? "star.fill" : "star")
                                .foregroundStyle(preferences.isFavorite(info.id) ? Color.dsAccent : Color.dsFaint)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(preferences.isFavorite(info.id)
                              ? "Remove from Favorites" : "Add to Favorites")
                        Image(systemName: preferences.symbol(for: info))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dsAccent)
                            .frame(width: 26)
                        Text(info.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.dsPaper)
                        Spacer()
                        Menu {
                            Button("Default") { preferences.setSymbol(info.symbolName, moduleID: info.id) }
                            Divider()
                            ForEach(MenuBarIconChoice.all) { option in
                                Button {
                                    preferences.setSymbol(option.symbol, moduleID: info.id)
                                } label: {
                                    Label(option.name, systemImage: option.symbol)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                HStack {
                    Spacer()
                    Button("Reset Icons") { preferences.resetSymbols() }
                        .buttonStyle(GhostButtonStyle())
                }
            }

            DSSettingsCard(title: "FreeKit Status Items") {
                ForEach(registry.modules.map(\.info).filter {
                    $0.status == .available && $0.ownsMenuBarItem
                        && $0.id != ModuleCatalog.menuBarManager.id
                }) { info in
                    HStack(spacing: 12) {
                        Image(systemName: preferences.symbol(for: info))
                            .foregroundStyle(
                                registry.showsMenuBarItem(id: info.id)
                                    ? Color.dsAccent : Color.dsMuted)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.dsPaper)
                            Text(registry.isEnabled(id: info.id) ? "Tool enabled" : "Tool disabled")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsFaint)
                        }
                        Spacer()
                        DSCheckbox(isOn: Binding(
                            get: { registry.showsMenuBarItem(id: info.id) },
                            set: { registry.setShowsMenuBarItem($0, id: info.id) }))
                            .disabled(!registry.isEnabled(id: info.id))
                            .opacity(registry.isEnabled(id: info.id) ? 1 : 0.4)
                    }
                    .frame(minHeight: 34)
                }
            }
        }
    }

    private func settingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dsPaper)
            Slider(value: value, in: range).tint(Color.dsAccent)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.dsMuted)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
