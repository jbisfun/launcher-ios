import Foundation
import Observation

/// AppsDatabase (Room) -> JSON files in Application Support/Launcher: the home screen items
/// (HomeScreenGridItemsDao) and the hidden icons (HiddenIconsDao). The app list itself
/// (AppLaunchersDao) is the fixed set of bundled apps.
@MainActor
@Observable
final class HomeStore {
    static let shared = HomeStore()

    private(set) var items: [HomeGridItem] = []
    private(set) var hiddenIcons: [HiddenIcon] = []

    @ObservationIgnored private var nextId: Int64 = 1
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private let config = LauncherConfig.shared

    private var itemsURL: URL { dir.appendingPathComponent("home_screen_grid_items.json") }
    private var hiddenURL: URL { dir.appendingPathComponent("hidden_icons.json") }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("Launcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        items = (try? Data(contentsOf: itemsURL)).flatMap { try? JSONDecoder().decode([HomeGridItem].self, from: $0) } ?? []
        hiddenIcons = (try? Data(contentsOf: hiddenURL)).flatMap { try? JSONDecoder().decode([HiddenIcon].self, from: $0) } ?? []
        nextId = max((items.compactMap(\.id).max() ?? 0), (hiddenIcons.compactMap(\.id).max() ?? 0)) + 1
        refreshLaunchers()
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: itemsURL, options: .atomic)
        try? JSONEncoder().encode(hiddenIcons).write(to: hiddenURL, options: .atomic)
    }

    // MARK: HomeScreenGridItemsDao

    func item(_ id: Int64?) -> HomeGridItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Items of a folder in their order.
    func folderItems(_ folderId: Int64?) -> [HomeGridItem] {
        guard let folderId else { return [] }
        return items.filter { $0.isSingleCellType && $0.parentId == folderId }.sorted { $0.left < $1.left }
    }

    @discardableResult
    func insert(_ item: inout HomeGridItem) -> Int64 {
        item.id = nextId
        nextId += 1
        items.append(item)
        save()
        return item.id!
    }

    func update(_ item: HomeGridItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id && item.id != nil }) else { return }
        items[i] = item
        save()
    }

    @discardableResult
    func updateItemTitle(_ title: String, id: Int64) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        items[i].title = title
        save()
        return true
    }

    /// deleteById: the item and, for folders, everything in it.
    func deleteById(_ id: Int64) {
        items.removeAll { $0.id == id || $0.parentId == id }
        save()
    }

    func shiftFolderItems(folderId: Int64, shiftFrom: Int, shiftBy: Int, excludingId: Int64?) {
        for i in items.indices where items[i].parentId == folderId && items[i].left > shiftFrom && items[i].id != excludingId {
            items[i].left += shiftBy
        }
        save()
    }

    func shiftPage(shiftFrom: Int, shiftBy: Int) {
        for i in items.indices where items[i].page > shiftFrom {
            items[i].page += shiftBy
        }
        save()
    }

    func deleteByPackageName(_ packageName: String) {
        let parents = Set(items.filter { $0.packageName == packageName }.compactMap(\.id))
        items.removeAll { $0.packageName == packageName && $0.type != .folder || ($0.parentId.map(parents.contains) ?? false) }
        save()
    }

    // MARK: launchers

    /// getAllAppLaunchers(): every bundled app that isn't hidden, sorted by title like AllAppsFragment.
    var launchers: [AppLauncher] {
        let hidden = Set(hiddenIcons.map(\.iconIdentifier))
        return BundledApp.allCases
            .map { AppLauncher(app: $0, title: $0.info.name) }
            .filter { !hidden.contains($0.launcherIdentifier) }
            .sorted { ($0.title.launcherNormalized.lowercased(), $0.packageName) < ($1.title.launcherNormalized.lowercased(), $1.packageName) }
    }

    /// refreshLaunchers(): drop home items of apps that aren't there anymore.
    func refreshLaunchers() {
        let known = Set(BundledApp.allCases.map(\.rawValue))
        for name in Set(items.filter { $0.type == .icon && !known.contains($0.packageName) }.map(\.packageName)) {
            deleteByPackageName(name)
        }
    }

    // MARK: HiddenIconsDao

    func hide(_ item: HomeGridItem) {
        guard !hiddenIcons.contains(where: { $0.iconIdentifier == item.itemIdentifier }) else { return }
        hiddenIcons.append(HiddenIcon(id: nextId, packageName: item.packageName, activityName: item.activityName, title: item.title))
        nextId += 1
        save()
    }

    func removeHiddenIcons(_ icons: [HiddenIcon]) {
        let ids = Set(icons.map(\.iconIdentifier))
        hiddenIcons.removeAll { ids.contains($0.iconIdentifier) }
        save()
    }

    // MARK: first run

    /// getDefaultAppPackages(): prefill the dock. Upstream puts the default dialer, SMS app, browser,
    /// app store and camera there; the bundled stand-ins are Phone, Messages, Contacts, Gallery and Camera.
    func initDefaultLayoutIfNeeded() {
        guard !config.wasHomeScreenInit else { return }
        let rowCount = config.homeRowCount
        let dock: [BundledApp] = [.phone, .messages, .contacts, .gallery, .camera]
        for (column, app) in dock.enumerated() where column < config.homeColumnCount {
            var item = HomeGridItem(id: nil, left: column, top: rowCount - 1, right: column, bottom: rowCount - 1, page: 0,
                                    packageName: app.rawValue, title: app.info.name, type: .icon, docked: true)
            insert(&item)
        }
        config.wasHomeScreenInit = true
    }
}
