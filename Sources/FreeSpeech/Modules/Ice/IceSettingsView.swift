import SwiftUI
import FreeSpeechCore

// Two checkbox lists in one pane: FreeKit's own tools (already backed by
// ModuleRegistry/Settings — this just surfaces the same state here too, so
// toggling in either place stays in sync) and other apps' menu bar icons
// (backed by IceModule's scan/drag machinery).
struct IceSettingsView: View {
    @ObservedObject var module: IceModule

    private var ownTools: [AppModule] {
        module.registry.modules
            .filter { $0.info.status == .available && $0.info.ownsMenuBarItem }
            .sorted { $0.info.displayName < $1.info.displayName }
    }

    // One row per distinct app: a few apps raise more than one status item,
    // and all of them move together, so they share a single checkbox.
    private var otherApps: [MenuBarAppEntry] {
        var seen = Set<String>()
        var result: [MenuBarAppEntry] = []
        for entry in module.entries where !seen.contains(entry.id) {
            seen.insert(entry.id)
            result.append(entry)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DSSettingsCard(title: "FreeKit Tools") {
                    if ownTools.isEmpty {
                        Text("No tools with a menu bar icon are available yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsFaint)
                    } else {
                        ForEach(ownTools, id: \.info.id) { toolModule in
                            DSToggleRow(
                                title: toolModule.info.displayName,
                                caption: toolModule.info.summary,
                                isOn: Binding(
                                    get: { module.registry.showsMenuBarItem(id: toolModule.info.id) },
                                    set: { module.registry.setShowsMenuBarItem($0, id: toolModule.info.id) }))
                        }
                    }
                }

                DSSettingsCard(title: "Other Apps") {
                    if !Permissions.accessibilityTrusted(promptIfNeeded: false) {
                        accessibilityBanner
                    }
                    if otherApps.isEmpty {
                        Text("No other apps currently have a menu bar icon.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsFaint)
                    } else {
                        ForEach(otherApps) { entry in
                            DSToggleRow(
                                title: entry.displayName,
                                caption: entry.bundleID == nil
                                    ? "Hides for this session only (no bundle identifier)." : nil,
                                isOn: Binding(
                                    get: { !module.isHidden(entry) },
                                    set: { module.setHidden(!$0, entry: entry) }))
                        }
                    }
                    Text("Click the chevron Ice adds to the menu bar to peek at hidden icons for a few seconds.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsFaint)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility needed to hide other apps' icons")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsPaper)
                Text("FreeKit's own tools above don't need this.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFaint)
            }
            Spacer()
            Button("Grant") { module.requestAccessibility() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(10)
        .background(Color.dsInk2, in: RoundedRectangle(cornerRadius: DS.radiusKeycap, style: .continuous))
    }
}
