import FossifyCommons
import Observation
import SwiftUI

enum SettingsRoute: Hashable {
    case customizeColors
    case about
    case hiddenIcons
}

@MainActor
@Observable
final class SettingsRouter {
    var path: [SettingsRoute] = []
    func push(_ r: SettingsRoute) { path.append(r) }
}

/// SettingsActivity as its own screen stack over the home screen.
struct LauncherSettingsRoot: View {
    @State private var router = SettingsRouter()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            SettingsView()
                .navigationDestination(for: SettingsRoute.self) { route in
                    Group {
                        switch route {
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .launcher)
                        case .hiddenIcons: HiddenIconsView()
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(router)
        .environment(LauncherConfig.shared)
        .fossifyTheme()
    }
}

private enum CountDialog: Identifiable {
    case drawerColumns, homeRows, homeColumns
    var id: Self { self }
}

/// SettingsActivity: every setting that applies on iOS (no "use English" / language / double tap
/// to lock, which iOS handles itself or doesn't allow).
struct SettingsView: View {
    @Environment(SettingsRouter.self) private var router
    @Environment(LauncherConfig.self) private var config
    @Environment(\.palette) private var palette
    @State private var dialog: CountDialog?

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings", onBack: nil, background: nil, tint: nil) {
                IconButton(icon: "info.circle") { router.push(.about) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Manage hidden icons") { router.push(.hiddenIcons) }

                    Text("App drawer").sectionHeader(palette)
                    SettingsItem("Column count", value: "\(config.drawerColumnCount)") { dialog = .drawerColumns }
                    SettingsToggle("Show search bar", isOn: $config.showSearchBar)
                    if config.showSearchBar {
                        SettingsToggle("Automatically show keyboard in drawer", isOn: $config.autoShowKeyboardInAppDrawer)
                    }
                    SettingsToggle("Close app drawer on opening an app", isOn: $config.closeAppDrawer)
                    SettingsToggle("Show app labels", isOn: $config.showDrawerAppLabels)

                    Text("Home screen").sectionHeader(palette)
                    SettingsItem("Row count", value: "\(config.homeRowCount)") { dialog = .homeRows }
                    SettingsItem("Column count", value: "\(config.homeColumnCount)") { dialog = .homeColumns }
                    SettingsToggle("Show app labels", isOn: $config.showHomeAppLabels)
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(item: $dialog) { d in
            switch d {
            case .drawerColumns:
                RadioDialog(title: nil, items: (1...MAX_COLUMN_COUNT).map { ($0, columns($0)) }, selected: config.drawerColumnCount) {
                    config.drawerColumnCount = $0
                }
                .fossifyTheme()
            case .homeRows:
                RadioDialog(title: nil, items: (MIN_ROW_COUNT...MAX_ROW_COUNT).map { ($0, $0 == 1 ? "1 row" : "\($0) rows") },
                            selected: config.homeRowCount) { config.homeRowCount = $0 }
                    .fossifyTheme()
            case .homeColumns:
                RadioDialog(title: nil, items: (MIN_COLUMN_COUNT...MAX_COLUMN_COUNT).map { ($0, columns($0)) },
                            selected: config.homeColumnCount) { config.homeColumnCount = $0 }
                    .fossifyTheme()
            }
        }
    }

    private func columns(_ n: Int) -> String { n == 1 ? "1 column" : "\(n) columns" }
}

extension AppInfo {
    public static let launcher = AppInfo(
        name: "Launcher", icon: "square.grid.3x3.fill", upstream: "Launcher", port: "launcher-ios", policy: "launcher"
    )
}

/// HiddenIconsActivity + HiddenIconsAdapter: select hidden icons and unhide them.
struct HiddenIconsView: View {
    @Environment(\.palette) private var palette
    @State private var selection = Set<String>()
    private let store = HomeStore.shared
    private let config = LauncherConfig.shared

    private var icons: [HiddenIcon] {
        store.hiddenIcons.filter { $0.app != nil }
            .sorted { ($0.title.launcherNormalized.lowercased(), $0.packageName) < ($1.title.launcherNormalized.lowercased(), $1.packageName) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if selection.isEmpty {
                TopBar(title: "Hidden icons")
            } else {
                ActionModeBar(count: selection.count, onClose: { selection.removeAll() }) {
                    IconButton(icon: "eye") {
                        store.removeHiddenIcons(icons.filter { selection.contains($0.iconIdentifier) })
                        selection.removeAll()
                    }
                }
            }
            let icons = icons
            if icons.isEmpty {
                Text("Some apps cannot be uninstalled due to system restrictions, but you can at least hide their icons to avoid seeing them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondaryText)
                    .padding(32)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, config.drawerColumnCount)), spacing: 8) {
                        ForEach(icons, id: \.iconIdentifier) { icon in
                            let selected = selection.contains(icon.iconIdentifier)
                            VStack(spacing: 4) {
                                AppIconImage(app: icon.app, size: 52)
                                Text(icon.title).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.primaryColor.opacity(0.3) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selection.isEmpty {
                                    toggleSelection(icon.iconIdentifier, in: &selection)
                                } else if selected {
                                    selection.remove(icon.iconIdentifier)
                                } else {
                                    selection.insert(icon.iconIdentifier)
                                }
                            }
                            .onLongPressGesture { toggleSelection(icon.iconIdentifier, in: &selection) }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
    }
}
