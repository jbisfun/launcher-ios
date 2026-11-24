import FossifyCommons
import Observation
import SwiftUI
import UIKit

struct ItemMenuRequest: Identifiable {
    let id = UUID()
    let item: HomeGridItem
    /// The rect the menu points at (the icon, or the widget).
    let anchor: CGRect
    let onAllApps: Bool
}

struct WidgetConfigRequest: Identifiable {
    let item: HomeGridItem
    let kind: HomeWidgetKind
    let app: BundledApp
    let isNew: Bool
    var id: String { item.widgetId }
}

private enum PageChangeArea { case left, middle, right }

/// MainActivity's touch handling plus HomeScreenGrid's state and logic (paging, dragging, folders,
/// widgets). The home view renders it; HomeTouchSurface, the widgets and the drawers feed it touches.
@MainActor
@Observable
final class HomeController {
    @ObservationIgnored let store = HomeStore.shared
    @ObservationIgnored let config = LauncherConfig.shared

    private(set) var geo: HomeGeometry?

    // AnimatedGridPager
    private(set) var currentPage = 0
    /// The page the view shows, fractional while swiping or animating.
    private(set) var pagePosition: CGFloat = 0
    private(set) var indicatorsAlpha: Double = 0
    @ObservationIgnored private var pageChangeEnabled = true
    @ObservationIgnored private var pageChangeLastArea = PageChangeArea.middle
    @ObservationIgnored private var pageChangeLastAreaEntryTime = Date.distantPast
    @ObservationIgnored private var fadeWork: DispatchWorkItem?

    // fragments (y offset; screenHeight = hidden)
    private(set) var screenHeight: CGFloat = 4000
    var allAppsY: CGFloat = 4000
    var widgetsY: CGFloat = 4000
    var isAllAppsExpanded: Bool { allAppsY < screenHeight }
    var isWidgetsExpanded: Bool { widgetsY < screenHeight }

    // grid
    private(set) var draggedItem: HomeGridItem?
    private(set) var dragPoint: CGPoint?
    private(set) var openFolderId: Int64?
    private(set) var resizedWidgetId: Int64?
    @ObservationIgnored private var draggingLeftFolderAt: Date?
    @ObservationIgnored private var draggingEnteredNewFolderAt: Date?
    @ObservationIgnored private var holdTimer: Timer?

    // menus, dialogs, screens
    var itemMenu: ItemMenuRequest?
    var mainMenuAnchor: CGPoint?
    var renaming: HomeGridItem?
    var aboutApp: BundledApp?
    var showSettings = false
    var showWallpapers = false
    var configuring: WidgetConfigRequest?
    @ObservationIgnored private var configureResult: Bool?
    var toast: String?
    var allAppsQuery = ""
    var widgetsQuery = ""
    private(set) var searchFocusRequest = 0
    private(set) var drawerResetRequest = 0
    @ObservationIgnored var launch: (BundledApp, URL?) -> Void = { _, _ in }
    /// StatusBarManager.expandNotificationsPanel: the launcher's own notification shade.
    @ObservationIgnored var expandNotifications: () -> Void = {}

    // MainActivity touch state
    @ObservationIgnored private var touchDown: CGPoint?
    @ObservationIgnored private var allAppsYAtDown: CGFloat = 0
    @ObservationIgnored private var widgetsYAtDown: CGFloat = 0
    @ObservationIgnored private var ignoreUpEvent = false
    @ObservationIgnored private var ignoreMoveEvents = false
    @ObservationIgnored private var ignoreXMoveEvents = false
    @ObservationIgnored private var ignoreYMoveEvents = false
    @ObservationIgnored private var hasMoved = false
    @ObservationIgnored private var longPressFired = false
    @ObservationIgnored private var longPressWork: DispatchWorkItem?
    @ObservationIgnored private var longPressedIcon: HomeGridItem?
    @ObservationIgnored private var lastUpEvent = Date.distantPast

    static let moveGestureThreshold: CGFloat = 20
    static let animationDuration = 0.15

    // MARK: setup

    func layout(size: CGSize, insets: EdgeInsets) {
        let newGeo = HomeGeometry(size: size, insets: insets, rows: config.homeRowCount, columns: config.homeColumnCount,
                                  showLabels: config.showHomeAppLabels)
        guard newGeo != geo else { return }
        let wasAllAppsHidden = !isAllAppsExpanded, wasWidgetsHidden = !isWidgetsExpanded
        geo = newGeo
        screenHeight = size.height
        if wasAllAppsHidden { allAppsY = size.height }
        if wasWidgetsHidden { widgetsY = size.height }
        if currentPage > maxPage() { skipToPage(maxPage()) }
    }

    func onAppear() {
        store.initDefaultLayoutIfNeeded()
        store.refreshLaunchers()
        // Widgets whose provider is gone are removed, like HomeScreenGrid.drawInto.
        for item in store.items where item.type == .widget && WidgetRegistry.kind(item.className) == nil {
            removeItemFromHomeScreen(item)
        }
    }

    /// onNewIntent (the navigation bar's Home): close the drawers, the folder and launcher screens.
    func homePressed() {
        if isAllAppsExpanded { hideAllApps() }
        if isWidgetsExpanded { hideWidgets() }
        allAppsQuery = ""
        closeFolder()
        hideResizeLines()
        itemMenu = nil
        mainMenuAnchor = nil
        showSettings = false
        showWallpapers = false
        renaming = nil
        aboutApp = nil
    }

    /// onBackPressedCompat: drawer search, then the drawers, the resize frame and the folder.
    func backPressed() {
        if itemMenu != nil || mainMenuAnchor != nil {
            itemMenu = nil
            mainMenuAnchor = nil
        } else if isAllAppsExpanded {
            if !allAppsQuery.isEmpty { allAppsQuery = "" } else { hideAllApps() }
        } else if isWidgetsExpanded {
            if !widgetsQuery.isEmpty { widgetsQuery = "" } else { hideWidgets() }
        } else if resizedWidgetId != nil {
            hideResizeLines()
        } else if openFolderId != nil {
            closeFolder()
        }
    }

    // MARK: queries

    func visibleOnCurrentPage(_ item: HomeGridItem) -> Bool {
        (item.page == currentPage || item.docked) && item.parentId == nil
    }

    func outOfBounds(_ item: HomeGridItem) -> Bool { geo?.outOfBounds(item) ?? true }

    /// getMaxPage.
    func maxPage() -> Int {
        store.items.filter { !$0.docked && !outOfBounds($0) }.map(\.page).max() ?? 0
    }

    var pageCount: Int { max(maxPage(), currentPage) + 1 }

    var openFolder: FolderLayout? {
        guard let geo, let folder = store.item(openFolderId) else { return nil }
        let items = store.folderItems(folder.id)
        return items.isEmpty ? nil : FolderLayout(folder: folder, items: items, geo: geo)
    }

    private var isSwipedOrAnimating: Bool { pagePosition != CGFloat(currentPage) }

    /// isClickingGridItem: only the open folder's items while a folder is open.
    func isClickingGridItem(_ p: CGPoint) -> HomeGridItem? {
        guard let geo, !isSwipedOrAnimating else { return nil }
        if openFolderId != nil {
            if let folder = openFolder {
                return folder.items.first { folder.clickableRect($0).contains(p) }
            }
            return nil
        }
        for item in store.items where visibleOnCurrentPage(item) && !outOfBounds(item) {
            if item.isSingleCellType {
                if geo.clickableRect(item).contains(p) { return item }
            } else if item.type == .widget, geo.widgetFrame(item).contains(p) {
                return item
            }
        }
        return nil
    }

    // MARK: touches (MainActivity.onTouchEvent + GestureDetector)

    func touchBegan(_ p: CGPoint) {
        touchDown = p
        allAppsYAtDown = allAppsY
        widgetsYAtDown = widgetsY
        ignoreUpEvent = false
        hasMoved = false
        longPressFired = false
        longPressWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasMoved, self.touchDown != nil else { return }
            self.longPressFired = true
            self.homeScreenLongPressed(p)
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func touchMoved(_ p: CGPoint) {
        guard let down = touchDown else {
            touchDown = p
            return
        }
        // some touches report moves for the whole long press; only real moves count
        let fingerMoved = abs(down.x - p.x) > Self.moveGestureThreshold || abs(down.y - p.y) > Self.moveGestureThreshold
        if fingerMoved {
            hasMoved = true
            longPressWork?.cancel()
        }

        if let icon = longPressedIcon, itemMenu != nil, fingerMoved {
            itemMenu = nil
            itemDraggingStarted(icon)
            hideAllApps()
        }

        if longPressedIcon != nil, fingerMoved {
            draggedItemMoved(p)
        }

        if fingerMoved && !ignoreMoveEvents {
            let diffY = down.y - p.y
            let diffX = down.x - p.x
            if abs(diffY) > abs(diffX) && !ignoreYMoveEvents {
                ignoreXMoveEvents = true
                if isWidgetsExpanded {
                    widgetsY = min(max(0, widgetsYAtDown - diffY), screenHeight)
                } else if longPressedIcon == nil {
                    allAppsY = min(max(0, allAppsYAtDown - diffY), screenHeight)
                }
            } else if abs(diffX) > abs(diffY) && !ignoreXMoveEvents {
                ignoreYMoveEvents = true
                setSwipeMovement(diffX)
            }
        }
    }

    func touchEnded(_ p: CGPoint, velocity: CGVector, cancelled: Bool = false) {
        longPressWork?.cancel()
        if longPressedIcon != nil || cancelled { lastUpEvent = Date() }

        if !cancelled && hasMoved && max(abs(velocity.dx), abs(velocity.dy)) > 350 && draggedItem == nil
            && Date().timeIntervalSince(lastUpEvent) >= 0.5 {
            if abs(velocity.dy) > abs(velocity.dx) {
                velocity.dy > 0 ? onFlingDown() : onFlingUp()
            } else {
                velocity.dx > 0 ? onFlingRight() : onFlingLeft()
            }
        } else if !cancelled && !hasMoved && !longPressFired && touchDown != nil {
            homeScreenClicked(p)
        }

        touchDown = nil
        ignoreMoveEvents = false
        longPressedIcon = nil
        itemDraggingStopped()

        if !ignoreUpEvent {
            if !ignoreYMoveEvents {
                if allAppsY < screenHeight * 0.5 {
                    showAllApps()
                } else if isAllAppsExpanded {
                    hideAllApps()
                }
                if widgetsY < screenHeight * 0.5 {
                    showWidgets()
                } else if isWidgetsExpanded {
                    hideWidgets()
                }
            }
            if !ignoreXMoveEvents { finalizeSwipe() }
        }
        if isSwipedOrAnimating && pageChangeEnabled { animatePageChange() }
        ignoreXMoveEvents = false
        ignoreYMoveEvents = false
    }

    private func onFlingUp() {
        if ignoreYMoveEvents { return }
        if !isWidgetsExpanded {
            ignoreUpEvent = true
            showAllApps()
        }
    }

    private func onFlingDown() {
        if ignoreYMoveEvents { return }
        ignoreUpEvent = true
        if isAllAppsExpanded {
            hideAllApps()
        } else if isWidgetsExpanded {
            hideWidgets()
        } else {
            expandNotifications()
        }
    }

    private func onFlingRight() {
        if ignoreXMoveEvents { return }
        ignoreUpEvent = true
        if !prevPage() { animatePageChange() }
    }

    private func onFlingLeft() {
        if ignoreXMoveEvents { return }
        ignoreUpEvent = true
        if !nextPage() { animatePageChange() }
    }

    private func homeScreenLongPressed(_ p: CGPoint) {
        if isAllAppsExpanded || isWidgetsExpanded { return }
        ignoreMoveEvents = true
        if let item = isClickingGridItem(p) {
            performItemLongClick(item)
            return
        }
        haptic()
        hideResizeLines()
        mainMenuAnchor = p
    }

    private func homeScreenClicked(_ p: CGPoint) {
        hideResizeLines()
        let item = isClickingGridItem(p)
        if let item { performItemClick(item) }
        if item?.type != .folder { closeFolder() }
    }

    private func performItemClick(_ item: HomeGridItem) {
        switch item.type {
        case .icon: if let app = item.app { launch(app, nil) }
        case .folder: openFolder(item)
        case .widget, .shortcut: break
        }
    }

    private func performItemLongClick(_ item: HomeGridItem) {
        haptic()
        showHomeIconMenu(item, onAllApps: false, anchor: nil)
    }

    func showHomeIconMenu(_ item: HomeGridItem, onAllApps: Bool, anchor: CGRect?) {
        hideResizeLines()
        longPressedIcon = item
        let rect: CGRect
        if let anchor {
            rect = anchor
        } else if let geo {
            if item.type == .widget {
                rect = geo.widgetFrame(item)
            } else if item.parentId != nil, let folder = openFolder {
                rect = folder.iconFrame(item)
            } else {
                rect = geo.iconFrame(item)
            }
        } else {
            rect = .zero
        }
        if itemMenu == nil {
            itemMenu = ItemMenuRequest(item: item, anchor: rect, onAllApps: onAllApps)
        }
    }

    // MARK: drawers (showFragment / hideFragment)

    func showAllApps() {
        withAnimation(.easeOut(duration: Self.animationDuration)) { allAppsY = 0 }
        fragmentExpanded()
        if config.showSearchBar && config.autoShowKeyboardInAppDrawer { searchFocusRequest += 1 }
    }

    func hideAllApps() {
        withAnimation(.easeOut(duration: Self.animationDuration)) { allAppsY = screenHeight }
        if draggedItem == nil { drawerResetRequest += 1 }
    }

    func showWidgets() {
        withAnimation(.easeOut(duration: Self.animationDuration)) { widgetsY = 0 }
        fragmentExpanded()
    }

    func hideWidgets() {
        withAnimation(.easeOut(duration: Self.animationDuration)) { widgetsY = screenHeight }
        widgetsQuery = ""
    }

    /// closeAppDrawer(delayed) after opening an app from the drawer.
    func closeAppDrawer(delayed: Bool) {
        guard isAllAppsExpanded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delayed ? 0.3 : 0)) { [weak self] in
            guard let self else { return }
            self.allAppsY = self.screenHeight
            self.drawerResetRequest += 1
        }
    }

    private func fragmentExpanded() {
        closeFolder()
        hideResizeLines()
    }

    /// A drawer pulled down while scrolled to its top (startHandlingTouches).
    func dragDrawer(widgets: Bool, by translation: CGFloat) {
        let y = min(max(0, translation), screenHeight)
        if widgets { widgetsY = y } else { allAppsY = y }
    }

    func releaseDrawer(widgets: Bool, flingDown: Bool) {
        let y = widgets ? widgetsY : allAppsY
        if flingDown || y >= screenHeight * 0.5 {
            widgets ? hideWidgets() : hideAllApps()
        } else {
            widgets ? showWidgets() : showAllApps()
        }
    }

    // MARK: drawer and widget list long presses

    /// AllAppsFragment.onAppLauncherLongPressed: the item menu; moving the finger drags it onto home.
    func drawerItemLongPressed(_ launcher: AppLauncher, at p: CGPoint, iconRect: CGRect) {
        haptic()
        startExternalTouch(at: p)
        let item = HomeGridItem(id: nil, left: -1, top: -1, right: -1, bottom: -1, page: 0, packageName: launcher.packageName,
                                title: launcher.title, type: .icon)
        showHomeIconMenu(item, onAllApps: true, anchor: iconRect)
    }

    /// WidgetsFragment.onWidgetLongPressed + MainActivity.widgetLongPressedOnList.
    func widgetLongPressedOnList(_ app: BundledApp, _ kind: HomeWidgetKind, at p: CGPoint) {
        let w = Int(kind.defaultSize.width.rounded()), h = Int(kind.defaultSize.height.rounded())
        if h > config.homeRowCount - 1 || w > config.homeColumnCount {
            toast = "Widget is too big for current home screen size"
            return
        }
        haptic()
        startExternalTouch(at: p)
        let item = HomeGridItem(id: nil, left: -1, top: -1, right: -1, bottom: -1, page: 0, packageName: app.rawValue,
                                title: "", type: .widget, className: kind.id, widthCells: max(1, w), heightCells: max(1, h))
        longPressedIcon = item
        hideWidgets()
        itemDraggingStarted(item)
    }

    private func startExternalTouch(at p: CGPoint) {
        touchDown = p
        hasMoved = false
        longPressFired = true
        ignoreMoveEvents = true
        ignoreXMoveEvents = true
        ignoreYMoveEvents = true
        ignoreUpEvent = true
    }

    // MARK: AnimatedGridPager

    private func setSwipeMovement(_ diffX: CGFloat) {
        guard draggedItem == nil, pageChangeEnabled, let geo else { return }
        if currentPage < maxPage() && diffX > 0 || currentPage > 0 && diffX < 0 {
            let percentage = min(max(-diffX / geo.size.width, -1), 1)
            pagePosition = CGFloat(currentPage) - percentage
            indicatorsAlpha = 1
            fadeWork?.cancel()
            closeFolder()
        }
    }

    private func finalizeSwipe() {
        let swiped = CGFloat(currentPage) - pagePosition
        guard swiped != 0 else { return }
        if abs(swiped) > 0.5 {
            currentPage = swiped > 0 ? currentPage - 1 : currentPage + 1
        }
        animatePageChange()
    }

    @discardableResult
    func nextPage() -> Bool {
        guard currentPage < maxPage(), pageChangeEnabled else { return false }
        currentPage += 1
        animatePageChange()
        return true
    }

    @discardableResult
    func prevPage() -> Bool {
        guard currentPage > 0, pageChangeEnabled else { return false }
        currentPage -= 1
        animatePageChange()
        return true
    }

    @discardableResult
    func skipToPage(_ target: Int) -> Bool {
        guard currentPage != target, target < maxPage() + 1 else { return false }
        currentPage = target
        animatePageChange()
        return true
    }

    private func nextOrAdditionalPage() -> Bool {
        guard currentPage < maxPage() + 1, pageChangeEnabled else { return false }
        currentPage += 1
        animatePageChange()
        return true
    }

    /// handlePageChange: overshooting slide to the current page, then fade the indicators.
    private func animatePageChange() {
        pageChangeEnabled = false
        closeFolder()
        fadeWork?.cancel()
        indicatorsAlpha = 1
        // never leave paging disabled if the completion doesn't come
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.pageChangeEnabled = true }
        guard pagePosition != CGFloat(currentPage) else {
            pageChangeEnabled = true
            scheduleIndicatorsFade()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            pagePosition = CGFloat(currentPage)
        } completion: { [weak self] in
            guard let self else { return }
            self.pageChangeEnabled = true
            self.clearPageChangeFlags()
            self.scheduleIndicatorsFade()
        }
    }

    private func scheduleIndicatorsFade() {
        fadeWork?.cancel()
        indicatorsAlpha = 1
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.draggedItem == nil else { return }
            withAnimation(.linear(duration: 0.3)) { self.indicatorsAlpha = 0 }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func clearPageChangeFlags() {
        pageChangeLastArea = .middle
        pageChangeLastAreaEntryTime = .distantPast
    }

    /// handleItemMovement: holding a dragged item at a screen side flips the page.
    private func handleItemMovement(_ x: CGFloat) {
        guard let geo else { return }
        indicatorsAlpha = 1
        fadeWork?.cancel()
        if x > geo.size.width - geo.right - geo.cellWidth / 2 {
            doWithPageChangeDelay(.right) { nextOrAdditionalPage() }
        } else if x < geo.left + geo.cellWidth / 2 {
            doWithPageChangeDelay(.left) { prevPage() }
        } else {
            clearPageChangeFlags()
        }
    }

    private func doWithPageChangeDelay(_ needed: PageChangeArea, _ change: () -> Bool) {
        if pageChangeLastArea != needed {
            pageChangeLastArea = needed
            pageChangeLastAreaEntryTime = Date()
        } else if Date().timeIntervalSince(pageChangeLastAreaEntryTime) > 0.5 {
            if change() { clearPageChangeFlags() }
        }
    }

    // MARK: folders

    func openFolder(_ folder: HomeGridItem) {
        if openFolderId == nil {
            withAnimation(.easeOut(duration: 0.2)) { openFolderId = folder.id }
        } else if openFolderId != folder.id {
            closeFolder()
        }
    }

    func closeFolder() {
        guard openFolderId != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { openFolderId = nil }
    }

    // MARK: dragging

    func itemDraggingStarted(_ item: HomeGridItem) {
        draggedItem = item
        if item.type == .widget { closeFolder() }
        holdTimer?.invalidate()
        // iOS sends no moves while the finger rests: re-check the hold thresholds (open/close folder, flip page).
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.dragPoint else { return }
                self.draggedItemMoved(p)
            }
        }
    }

    func draggedItemMoved(_ p: CGPoint) {
        guard let dragged = draggedItem, let geo else { return }

        if let folder = openFolder {
            if folder.drawingRect.contains(p) {
                draggingLeftFolderAt = nil
            } else if let left = draggingLeftFolderAt {
                if Date().timeIntervalSince(left) > 0.3 { closeFolder() }
            } else {
                draggingLeftFolderAt = Date()
            }
        }

        dragPoint = p

        if dragged.type != .folder && dragged.type != .widget {
            let cell = geo.closestCell(to: p)
            let coveredFolder = store.items.first {
                $0.type == .folder && $0.left == cell.x && $0.top == cell.y && visibleOnCurrentPage($0)
            }
            if let coveredFolder, coveredFolder.id != dragged.id, openFolderId == nil {
                if let entered = draggingEnteredNewFolderAt {
                    if Date().timeIntervalSince(entered) > 0.5 {
                        if store.folderItems(coveredFolder.id).count >= HomeGridItem.folderMaxCapacity
                            && dragged.parentId != coveredFolder.id {
                            haptic()
                            draggingEnteredNewFolderAt = nil
                        } else {
                            openFolder(coveredFolder)
                        }
                    }
                } else {
                    draggingEnteredNewFolderAt = Date()
                }
            } else {
                draggingEnteredNewFolderAt = nil
            }
        }

        handleItemMovement(p.x)
    }

    /// Figure out at which cell the item was dropped.
    func itemDraggingStopped() {
        holdTimer?.invalidate()
        holdTimer = nil
        guard let dragged = draggedItem else { return }
        scheduleIndicatorsFade()
        clearPageChangeFlags()
        draggingEnteredNewFolderAt = nil
        draggingLeftFolderAt = nil
        if dragPoint != nil {
            switch dragged.type {
            case .folder: moveItem()
            case .icon, .shortcut: addAppIconOrShortcut()
            case .widget: addWidget()
            }
        }
        draggedItem = nil
        dragPoint = nil
    }

    private func moveItem() {
        guard let geo, let p = dragPoint, var item = store.item(draggedItem?.id) else { return }
        let cell = geo.closestCell(to: p)
        var valid = true
        // no moving folders into the dock
        if item.type == .folder && cell.y == geo.rowCount - 1 {
            valid = false
        } else {
            for other in store.items where visibleOnCurrentPage(other) && other.covers(cell, rowCount: geo.rowCount) {
                if other.type == .widget && outOfBounds(other) {
                    removeItemFromHomeScreen(other)
                } else {
                    valid = false
                }
            }
        }
        guard valid else { return }
        let oldPage = item.page
        item.left = cell.x
        item.top = cell.y
        item.right = cell.x
        item.bottom = cell.y
        item.page = currentPage
        item.docked = cell.y == geo.rowCount - 1
        store.update(item)
        deletePageIfEmpty(oldPage, movedPage: item.page)
    }

    private func addAppIconOrShortcut() {
        guard let geo, let p = dragPoint, let dragged = draggedItem else { return }
        var valid = false
        var potentialParent: HomeGridItem?
        var xIndex = 0, yIndex = 0

        if let folder = openFolder, folder.itemsDrawingRect.contains(p) {
            let centers = folder.itemsGridCenters
            xIndex = centers.min { distance($0.1, p) < distance($1.1, p) }?.0 ?? 0
            valid = true
            potentialParent = folder.folder
            yIndex = 0
        } else {
            let cell = geo.closestCell(to: p)
            xIndex = cell.x
            yIndex = cell.y
            valid = true
            for item in store.items where visibleOnCurrentPage(item) && (dragged.id == nil || item.id != dragged.id) {
                guard item.covers(cell, rowCount: geo.rowCount) else { continue }
                if item.type != .widget && !item.docked {
                    potentialParent = item
                } else if item.type == .widget && outOfBounds(item) {
                    removeItemFromHomeScreen(item)
                } else {
                    valid = false
                }
            }
        }

        guard valid else {
            haptic()
            return
        }
        let draggedHome = dragged.id == nil ? nil : store.item(dragged.id)
        if let parent = potentialParent {
            if parent.type == .folder {
                addAppIcon(draggedHome, xIndex, yIndex, newParentId: parent.id, toFolderEnd: parent.id != openFolderId)
            } else {
                var folder = parent
                folder.id = nil
                folder.type = .folder
                folder.title = "Folder"
                let newId = store.insert(&folder)
                var child = parent
                child.parentId = newId
                child.left = 0
                store.update(child)
                addAppIcon(draggedHome, xIndex, yIndex, newParentId: newId)
            }
        } else {
            addAppIcon(draggedHome, xIndex, yIndex, newParentId: nil)
        }
    }

    private func addAppIcon(_ draggedHome: HomeGridItem?, _ xIndex: Int, _ yIndex: Int, newParentId: Int64?, toFolderEnd: Bool = true) {
        guard let geo, let dragged = draggedItem else { return }
        if let newParentId, newParentId != draggedHome?.parentId,
           store.folderItems(newParentId).count >= HomeGridItem.folderMaxCapacity {
            haptic()
            return
        }

        let finalXIndex: Int
        if let newParentId {
            let folderItems = store.folderItems(newParentId)
            if toFolderEnd {
                finalXIndex = folderItems.map { $0.left + 1 }.max() ?? 0
            } else {
                finalXIndex = min(xIndex, folderItems.map { draggedHome?.parentId == newParentId ? $0.left : $0.left + 1 }.max() ?? 0)
            }
        } else {
            finalXIndex = xIndex
        }

        if var item = draggedHome {
            // moving an existing home screen item from one place to another
            let oldParentId = item.parentId, oldLeft = item.left, oldPage = item.page
            item.left = finalXIndex
            item.top = yIndex
            item.right = finalXIndex
            item.bottom = yIndex
            item.page = currentPage
            item.docked = yIndex == geo.rowCount - 1
            item.parentId = newParentId
            store.update(item)

            if let oldParentId, store.folderItems(oldParentId).isEmpty {
                store.deleteById(oldParentId)
                if openFolderId == oldParentId { openFolderId = nil }
            } else if let oldParentId, !store.items.contains(where: { $0.parentId == oldParentId && $0.left == oldLeft }) {
                store.shiftFolderItems(folderId: oldParentId, shiftFrom: oldLeft, shiftBy: -1, excludingId: item.id)
            }

            item = store.item(item.id) ?? item
            if let newParentId, newParentId != oldParentId || item.left != oldLeft {
                store.shiftFolderItems(folderId: newParentId, shiftFrom: item.left - 1, shiftBy: 1, excludingId: item.id)
            }
            deletePageIfEmpty(oldPage, movedPage: item.page)
        } else {
            // dragging a new item onto the home screen from the drawer
            var item = HomeGridItem(id: nil, left: finalXIndex, top: yIndex, right: finalXIndex, bottom: yIndex, page: currentPage,
                                    packageName: dragged.packageName, activityName: dragged.activityName, title: dragged.title,
                                    type: dragged.type, docked: yIndex == geo.rowCount - 1, parentId: newParentId)
            store.insert(&item)
            if let newParentId {
                store.shiftFolderItems(folderId: newParentId, shiftFrom: item.left - 1, shiftBy: 1, excludingId: item.id)
            }
        }
    }

    private func addWidget() {
        guard let geo, let p = dragPoint, let dragged = draggedItem else { return }
        let rect = geo.widgetOccupiedRect(dragged, at: geo.closestCell(to: p))
        var targets = Set<GridCell>()
        for x in rect.left...rect.right {
            for y in rect.top...rect.bottom { targets.insert(GridCell(x: x, y: y)) }
        }

        var allEmpty = true
        for item in store.items where visibleOnCurrentPage(item) && (dragged.id == nil || item.id != dragged.id) {
            guard targets.contains(where: { item.covers($0, rowCount: geo.rowCount) }) else { continue }
            if item.type == .widget && outOfBounds(item) {
                removeItemFromHomeScreen(item)
            } else {
                allEmpty = false
            }
        }
        guard allEmpty else {
            haptic()
            return
        }

        var widget = dragged
        let oldPage = widget.page
        widget.left = rect.left
        widget.top = rect.top
        widget.right = rect.right
        widget.bottom = rect.bottom
        widget.page = currentPage
        widget.docked = false
        widget.parentId = nil
        if widget.id == nil {
            // store the new widget at creating it, else just move the existing one
            widget.widgetId = UUID().uuidString
            store.insert(&widget)
            bindWidget(widget)
        } else {
            store.update(widget)
            deletePageIfEmpty(oldPage, movedPage: widget.page)
        }
    }

    /// bindWidget: run the widget's configure screen; cancelling it removes the widget again.
    private func bindWidget(_ item: HomeGridItem) {
        guard let (app, kind) = WidgetRegistry.kind(item.className) else {
            removeItemFromHomeScreen(item)
            return
        }
        if kind.configure != nil {
            configureResult = nil
            configuring = WidgetConfigRequest(item: item, kind: kind, app: app, isNew: true)
        }
    }

    func reconfigure(_ item: HomeGridItem) {
        guard let (app, kind) = WidgetRegistry.kind(item.className), kind.configure != nil else { return }
        configureResult = nil
        configuring = WidgetConfigRequest(item: item, kind: kind, app: app, isNew: false)
    }

    func configureDone(_ ok: Bool) {
        configureResult = ok
        configuring = nil
    }

    /// The configure sheet went away (done or swiped down: Android's back = RESULT_CANCELED).
    func configureDismissed(_ request: WidgetConfigRequest) {
        if request.isNew && configureResult != true, let item = store.item(request.item.id) {
            removeItemFromHomeScreen(item)
        }
        configureResult = nil
        if currentPage > maxPage() { prevPage() }
    }

    func widgetContext(_ item: HomeGridItem) -> HomeWidgetContext {
        let app = item.app
        return HomeWidgetContext(instanceID: item.widgetId.isEmpty ? "preview-\(item.className)" : item.widgetId,
                                 size: CGSize(width: item.widthInCells, height: item.heightInCells),
                                 openApp: { [weak self] url in
                                     if let app { self?.launch(app, url) }
                                 })
    }

    // MARK: resizing (MyAppWidgetResizeFrame)

    func widgetLongPressed(_ item: HomeGridItem) {
        resizedWidgetId = item.id
    }

    func hideResizeLines() {
        resizedWidgetId = nil
    }

    /// onResizeListener: the frame snapped to new cells.
    func resizeWidget(_ id: Int64, to cells: (left: Int, top: Int, right: Int, bottom: Int)) {
        guard let geo, var item = store.item(id) else { return }
        item.left = cells.left
        item.top = cells.top
        item.right = cells.right
        item.bottom = min(cells.bottom, geo.rowCount - 2)
        item.docked = false
        item.parentId = nil
        store.update(item)
    }

    /// Cells taken by everything on the page but the resized widget.
    func occupiedCells(excluding id: Int64) -> Set<GridCell> {
        var cells = Set<GridCell>()
        for item in store.items where visibleOnCurrentPage(item) && !outOfBounds(item) && item.id != id {
            for x in item.left...max(item.left, item.right) {
                for y in item.top...max(item.top, item.bottom) { cells.insert(GridCell(x: x, y: y)) }
            }
        }
        return cells
    }

    // MARK: removing

    func removeAppIcon(_ item: HomeGridItem) {
        removeItemFromHomeScreen(item)
        if currentPage > maxPage() { prevPage() }
    }

    func removeItemFromHomeScreen(_ item: HomeGridItem) {
        if let id = item.id {
            if item.type == .widget, !item.widgetId.isEmpty {
                // the widget's own settings go with it (appWidgetHost.deleteAppWidgetId)
                let prefix = "widget_\(item.widgetId)_"
                let defaults = UserDefaults.standard
                for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) { defaults.removeObject(forKey: key) }
            }
            store.deleteById(id)
            if let parentId = item.parentId {
                store.shiftFolderItems(folderId: parentId, shiftFrom: item.left, shiftBy: -1, excludingId: id)
                if store.folderItems(parentId).isEmpty {
                    store.deleteById(parentId)
                    if openFolderId == parentId { openFolderId = nil }
                }
            }
            if openFolderId == id { openFolderId = nil }
            if resizedWidgetId == id { resizedWidgetId = nil }
        }
        if item.page != 0 && !store.items.contains(where: { $0.page == item.page && $0.id != item.id && $0.parentId == nil }) {
            deletePage(item.page)
        }
    }

    private func deletePageIfEmpty(_ oldPage: Int, movedPage: Int) {
        if movedPage != oldPage && oldPage != 0 && !store.items.contains(where: { $0.page == oldPage && $0.parentId == nil }) {
            deletePage(oldPage)
        }
    }

    private func deletePage(_ page: Int) {
        store.shiftPage(shiftFrom: page, shiftBy: -1)
        if currentPage > page {
            // the pages after it slid one to the left
            currentPage -= 1
            pagePosition = CGFloat(currentPage)
        }
        if currentPage > maxPage() {
            DispatchQueue.main.async { [weak self] in self?.prevPage() }
        }
    }

    // MARK: item menu actions

    func hideIcon(_ item: HomeGridItem) {
        store.hide(item)
    }

    func renameItem(_ item: HomeGridItem) {
        renaming = item
    }

    // MARK: helpers

    func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { abs(a.x - b.x) + abs(a.y - b.y) }
}
