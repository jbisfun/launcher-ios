import Foundation

/// helpers/Constants.kt ITEM_TYPE_*. Shortcuts (Android pinned shortcuts) have no iOS counterpart.
enum HomeItemType: Int, Codable {
    case icon = 0, widget = 1, shortcut = 2, folder = 3
}

struct GridCell: Hashable {
    var x: Int
    var y: Int
}

/// models/HomeScreenGridItem.kt. Grid cells are 0-5 by default; icons and folders occupy one cell,
/// widgets can be bigger. Items inside a folder keep their order in `left`.
struct HomeGridItem: Codable, Equatable {
    var id: Int64?
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
    var page: Int
    /// The BundledApp raw value.
    var packageName: String
    var activityName: String = ""
    var title: String
    var type: HomeItemType
    /// Widgets: the HomeWidgetKind id (Android: provider class name).
    var className: String = ""
    /// Widgets: the HomeWidgetContext instanceID (Android: appWidgetId).
    var widgetId: String = ""
    /// Always at the bottom of the screen: page, top and bottom don't matter for it.
    var docked: Bool = false
    /// The folder this item is in, if any.
    var parentId: Int64?
    /// Size of a widget not placed yet.
    var widthCells: Int = 1
    var heightCells: Int = 1

    static let folderMaxCapacity = 16

    var widthInCells: Int { right == -1 || left == -1 ? widthCells : right - left + 1 }
    var heightInCells: Int { bottom == -1 || top == -1 ? heightCells : bottom - top + 1 }

    func dockAdjustedTop(_ rowCount: Int) -> Int { docked ? rowCount - 1 : top }
    func dockAdjustedBottom(_ rowCount: Int) -> Int { docked ? rowCount - 1 : bottom }
    func topLeft(_ rowCount: Int) -> GridCell { GridCell(x: left, y: dockAdjustedTop(rowCount)) }

    var itemIdentifier: String { "\(packageName)/\(activityName)" }
    var app: BundledApp? { BundledApp(rawValue: packageName) }
    var isSingleCellType: Bool { type == .icon || type == .shortcut || type == .folder }

    func covers(_ cell: GridCell, rowCount: Int) -> Bool {
        (left...max(left, right)).contains(cell.x)
            && (dockAdjustedTop(rowCount)...max(dockAdjustedTop(rowCount), dockAdjustedBottom(rowCount))).contains(cell.y)
    }
}

/// models/HiddenIcon.kt.
struct HiddenIcon: Codable, Hashable {
    var id: Int64?
    var packageName: String
    var activityName: String
    var title: String

    var iconIdentifier: String { "\(packageName)/\(activityName)" }
    var app: BundledApp? { BundledApp(rawValue: packageName) }
}

/// models/AppLauncher.kt: an app shown in the drawer.
struct AppLauncher: Identifiable, Equatable {
    let app: BundledApp
    var title: String

    var packageName: String { app.rawValue }
    var activityName: String { "" }
    var launcherIdentifier: String { "\(packageName)/\(activityName)" }
    var id: String { launcherIdentifier }
    var bubbleText: String { title }
}

extension String {
    /// normalizeString(): strip accents for sorting and searching.
    var launcherNormalized: String { folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
}
