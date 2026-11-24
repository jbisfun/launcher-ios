import Foundation
import Observation

// helpers/Constants.kt: default home screen grid size and its limits.
let ROW_COUNT = 6
let COLUMN_COUNT = 5
let MIN_ROW_COUNT = 2
let MAX_ROW_COUNT = 15
let MIN_COLUMN_COUNT = 2
let MAX_COLUMN_COUNT = 15
/// integers.xml portrait_column_count.
let PORTRAIT_DRAWER_COLUMN_COUNT = 5
let DEFAULT_WALLPAPER = "bundle:Android 14"

/// Port of the launcher's Config (SharedPreferences -> UserDefaults). Every key is prefixed with
/// `launcher_` since all bundled apps share UserDefaults; colors live in FossifyCommons.BaseConfig.
@Observable
final class LauncherConfig {
    static let shared = LauncherConfig()

    @ObservationIgnored private let d = UserDefaults.standard

    var wasHomeScreenInit: Bool { didSet { d.set(wasHomeScreenInit, forKey: "launcher_was_home_screen_init") } }
    var homeRowCount: Int { didSet { d.set(homeRowCount, forKey: "launcher_home_row_count") } }
    var homeColumnCount: Int { didSet { d.set(homeColumnCount, forKey: "launcher_home_column_count") } }
    var drawerColumnCount: Int { didSet { d.set(drawerColumnCount, forKey: "launcher_drawer_column_count") } }
    var showSearchBar: Bool { didSet { d.set(showSearchBar, forKey: "launcher_show_search_bar") } }
    var closeAppDrawer: Bool { didSet { d.set(closeAppDrawer, forKey: "launcher_close_app_drawer") } }
    var autoShowKeyboardInAppDrawer: Bool {
        didSet { d.set(autoShowKeyboardInAppDrawer, forKey: "launcher_auto_show_keyboard_in_app_drawer") }
    }
    var showDrawerAppLabels: Bool { didSet { d.set(showDrawerAppLabels, forKey: "launcher_show_drawer_app_labels") } }
    var showHomeAppLabels: Bool { didSet { d.set(showHomeAppLabels, forKey: "launcher_show_home_app_labels") } }
    /// iOS: the home background. "bundle:<name>" (Wallpapers.bundle), "custom" (picked from Photos) or "" (theme background).
    var wallpaper: String { didSet { d.set(wallpaper, forKey: "launcher_wallpaper") } }
    /// Bumped whenever the custom wallpaper file is replaced.
    var wallpaperRevision: Int { didSet { d.set(wallpaperRevision, forKey: "launcher_wallpaper_revision") } }
    /// Settings.Secure.NAVIGATION_MODE: 3-button (default) or gesture navigation.
    var navigationMode: NavigationMode { didSet { d.set(navigationMode.rawValue, forKey: "launcher_navigation_mode") } }
    /// Settings.Secure "sysui_qs_tiles": the quick settings tiles, in order.
    var qsTiles: [QSTileSpec] { didSet { d.set(qsTiles.map(\.rawValue), forKey: "launcher_qs_tiles") } }

    private init() {
        wasHomeScreenInit = d.bool(forKey: "launcher_was_home_screen_init")
        homeRowCount = d.object(forKey: "launcher_home_row_count") as? Int ?? ROW_COUNT
        homeColumnCount = d.object(forKey: "launcher_home_column_count") as? Int ?? COLUMN_COUNT
        drawerColumnCount = d.object(forKey: "launcher_drawer_column_count") as? Int ?? PORTRAIT_DRAWER_COLUMN_COUNT
        showSearchBar = d.object(forKey: "launcher_show_search_bar") as? Bool ?? true
        closeAppDrawer = d.bool(forKey: "launcher_close_app_drawer")
        autoShowKeyboardInAppDrawer = d.bool(forKey: "launcher_auto_show_keyboard_in_app_drawer")
        showDrawerAppLabels = d.object(forKey: "launcher_show_drawer_app_labels") as? Bool ?? true
        showHomeAppLabels = d.object(forKey: "launcher_show_home_app_labels") as? Bool ?? true
        wallpaper = d.string(forKey: "launcher_wallpaper") ?? DEFAULT_WALLPAPER
        wallpaperRevision = d.integer(forKey: "launcher_wallpaper_revision")
        navigationMode = NavigationMode(rawValue: d.integer(forKey: "launcher_navigation_mode")) ?? .threeButton
        qsTiles = (d.stringArray(forKey: "launcher_qs_tiles")?.compactMap(QSTileSpec.init(rawValue:))) ?? QSTileSpec.defaults
    }
}

/// WindowManagerPolicyConstants.NAV_BAR_MODE_* (2-button is gone from AOSP's picker too).
enum NavigationMode: Int, CaseIterable {
    case threeButton = 0
    case gestural = 2

    var title: String { self == .gestural ? "Gesture navigation" : "3-button navigation" }
    var summary: String {
        self == .gestural
            ? "To go Home, swipe up from the bottom of the screen. To switch apps, swipe up from the bottom, hold, then release. To go back, swipe from either the left or right edge."
            : "Go back, Home, and switch apps with buttons at the bottom of your screen."
    }
}
