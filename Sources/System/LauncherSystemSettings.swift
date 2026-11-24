import FossifyCommons
import KeyboardKit
import SwiftUI

/// Launcher-owned settings registered with commons' SystemSettingsRegistry, so the Settings app
/// shows them in its AOSP categories, plus the bundled apps for Settings > Apps.
@MainActor
enum LauncherSystemSettings {
    static func register() {
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "launcher.wallpaper", category: .wallpaper, title: "Wallpaper", summary: "Home screen background",
            icon: "photo.on.rectangle", keywords: ["background", "home screen"]
        ) { page(WallpaperPickerView()) })
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "launcher.homeScreen", category: .display, title: "Home screen", summary: "Grid size, labels, app drawer",
            icon: "square.grid.3x3", keywords: ["launcher", "rows", "columns", "drawer", "labels", "search bar"]
        ) { page(HomeScreenSettingsView()) })
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "launcher.navigationMode", category: .system, title: "Navigation mode",
            summary: LauncherConfig.shared.navigationMode.title, icon: "rectangle.bottomthird.inset.filled",
            keywords: ["gesture", "3-button", "navigation bar", "back", "home", "recents", "overview"]
        ) { page(NavigationModeView()) })
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "launcher.quickSettingsTiles", category: .notifications, title: "Quick settings tiles",
            summary: "Edit the tiles of the notification shade", icon: "square.grid.2x2",
            keywords: ["quick settings", "tiles", "shade", "flashlight", "control center"]
        ) { page(QSEditView()) })
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "launcher.hiddenApps", category: .apps, title: "Hidden apps", summary: "Icons hidden from the app drawer",
            icon: "eye.slash", keywords: ["hide", "icons", "drawer"]
        ) { page(HiddenIconsView()) })
        // Fossify Keyboard's own settings (its root opens them for fossify-keyboard://settings).
        SystemSettingsRegistry.register(SystemSettingsEntry(
            id: "keyboard.settings", category: .system, title: "Fossify Keyboard", summary: "On-screen keyboard settings",
            icon: "keyboard", keywords: ["keyboard", "languages", "vibration", "clipboard"]
        ) { AnyView(KeyboardRoot(openURL: URL(string: "\(KeyboardRoot.urlScheme)://settings"))) })

        SystemSettingsRegistry.apps = BundledApp.allCases.map { app in
            SystemAppEntry(info: app.info, icon: app.icon, open: { SystemUI.shared.launch(app) })
        }
    }

    private static func page<V: View>(_ view: V) -> AnyView {
        AnyView(view
            .toolbar(.hidden, for: .navigationBar)
            .environment(LauncherConfig.shared)
            .fossifyTheme()
            .paletteBackground())
    }
}

/// The app drawer and home screen sections of the launcher settings, on their own.
struct HomeScreenSettingsView: View {
    @Environment(\.palette) private var palette
    @State private var config = LauncherConfig.shared
    @State private var dialog: HomeCountDialog?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Home screen")
            ScrollView {
                VStack(spacing: 0) {
                    HomeScreenSettingsSections(config: config, dialog: $dialog)
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .homeCountDialogs($dialog, config: config)
    }
}

enum HomeCountDialog: Identifiable {
    case drawerColumns, homeRows, homeColumns
    var id: Self { self }
}

/// "App drawer" + "Home screen" rows of SettingsActivity.
struct HomeScreenSettingsSections: View {
    @Environment(\.palette) private var palette
    @Bindable var config: LauncherConfig
    @Binding var dialog: HomeCountDialog?

    var body: some View {
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
}

extension View {
    func homeCountDialogs(_ dialog: Binding<HomeCountDialog?>, config: LauncherConfig) -> some View {
        func columns(_ n: Int) -> String { n == 1 ? "1 column" : "\(n) columns" }
        return sheet(item: dialog) { d in
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
}

/// Settings > System > Gestures > System navigation (SystemNavigationGestureSettings).
struct NavigationModeView: View {
    @Environment(\.palette) private var palette
    @State private var config = LauncherConfig.shared

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "System navigation")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([NavigationMode.gestural, .threeButton], id: \.rawValue) { mode in
                        Button {
                            config.navigationMode = mode
                            SystemUI.shared.refreshInsets()
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: config.navigationMode == mode ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(config.navigationMode == mode ? palette.primaryColor : palette.secondaryText)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.title).font(.system(size: palette.fontSize))
                                    Text(mode.summary).font(.system(size: palette.fontSize * 0.8)).foregroundStyle(palette.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(palette.textColor)
        .background(palette.backgroundColor.ignoresSafeArea())
    }
}
