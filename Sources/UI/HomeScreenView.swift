import FossifyCommons
import SwiftUI

extension View {
    /// Places a view at an absolute rect inside a top-leading ZStack.
    func placed(_ r: CGRect) -> some View {
        frame(width: max(r.width, 0), height: max(r.height, 0)).offset(x: r.minX, y: r.minY)
    }
}

/// activity_main: the paged home grid with its dock and widgets, the open folder, the dragged
/// item, the page indicators, and the app drawer and widgets list sliding over it.
struct HomeScreenView: View {
    @Environment(\.palette) private var palette
    let controller: HomeController
    let wallpaper: UIImage?

    private var store: HomeStore { controller.store }
    private var config: LauncherConfig { controller.config }

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { inner in
                let key = "\(inner.size.width)x\(inner.size.height) \(insets.top) \(insets.bottom) \(insets.leading) \(insets.trailing) "
                    + "\(config.homeRowCount) \(config.homeColumnCount) \(config.showHomeAppLabels)"
                content(size: inner.size)
                    .onChange(of: key, initial: true) { controller.layout(size: inner.size, insets: insets) }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
    }

    private var onWallpaper: Bool { wallpaper != nil }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            background(size)
            HomeTouchSurface(controller: controller).frame(width: size.width, height: size.height)
            if let geo = controller.geo {
                gridLayer(geo).allowsHitTesting(false)
                widgetsLayer(geo)
                folderLayer(geo).allowsHitTesting(false)
                indicators(geo).allowsHitTesting(false)
                if let id = controller.resizedWidgetId, let item = store.item(id) {
                    WidgetResizeFrame(controller: controller, item: item, geo: geo).id(id)
                }
                dragLayer(geo).allowsHitTesting(false)
            }
            AllAppsView(controller: controller)
                .frame(width: size.width, height: size.height)
                .offset(y: controller.allAppsY)
            WidgetsListView(controller: controller)
                .frame(width: size.width, height: size.height)
                .offset(y: controller.widgetsY)
            MenusOverlay(controller: controller, size: size)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "home")
        .clipped()
    }

    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        if let wallpaper {
            Image(uiImage: wallpaper).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        } else {
            palette.backgroundColor.frame(width: size.width, height: size.height)
        }
    }

    // MARK: grid

    private func pageOffset(_ page: Int, _ geo: HomeGeometry) -> CGFloat {
        (CGFloat(page) - controller.pagePosition) * geo.size.width
    }

    private func isOnScreen(_ page: Int) -> Bool { abs(CGFloat(page) - controller.pagePosition) < 1 }

    @ViewBuilder
    private func gridLayer(_ geo: HomeGeometry) -> some View {
        let items = store.items.filter {
            $0.isSingleCellType && $0.parentId == nil && !geo.outOfBounds($0) && ($0.docked || isOnScreen($0.page))
                && $0.id != controller.draggedItem?.id
        }
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let dx = item.docked ? 0 : pageOffset(item.page, geo)
                let frame = geo.iconFrame(item).offsetBy(dx: dx, dy: 0)
                itemIcon(item, size: geo.iconSize).placed(frame)
                if !item.docked && geo.showLabels && !item.title.isEmpty {
                    let w = geo.cellWidth - 2 * HomeGeometry.labelSideMargin
                    HomeLabel(title: item.title, width: w, onWallpaper: onWallpaper)
                        .offset(x: frame.midX - w / 2, y: frame.maxY + HomeGeometry.labelSideMargin)
                }
            }
        }
    }

    @ViewBuilder
    private func itemIcon(_ item: HomeGridItem, size: CGFloat) -> some View {
        if item.type == .folder {
            FolderIconImage(items: store.folderItems(item.id), size: size)
        } else {
            AppIconImage(app: item.app, size: size)
        }
    }

    @ViewBuilder
    private func widgetsLayer(_ geo: HomeGeometry) -> some View {
        let widgets = store.items.filter {
            $0.type == .widget && !geo.outOfBounds($0) && (isOnScreen($0.page) || $0.id == controller.draggedItem?.id)
        }
        ZStack(alignment: .topLeading) {
            ForEach(widgets, id: \.id) { item in
                if let (_, kind) = WidgetRegistry.kind(item.className) {
                    // the dragged widget stays (invisible) so its touch keeps going (beGone upstream)
                    HomeWidgetView(controller: controller, item: item, kind: kind)
                        .opacity(item.id == controller.draggedItem?.id ? 0 : 1)
                        .placed(geo.widgetFrame(item).offsetBy(dx: pageOffset(item.page, geo), dy: 0))
                }
            }
        }
    }

    @ViewBuilder
    private func folderLayer(_ geo: HomeGeometry) -> some View {
        if let folder = controller.openFolder {
            let rect = folder.drawingRect.offsetBy(dx: pageOffset(folder.folder.page, geo), dy: 0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: HomeGeometry.roundedCornerRadius).fill(palette.backgroundColor)
                    .frame(width: rect.width, height: rect.height)
                Text(folder.folder.title)
                    .font(.system(size: HomeGeometry.folderTitleFontSize))
                    .foregroundStyle(palette.textColor)
                    .lineLimit(1)
                    .frame(width: rect.width - 2 * HomeGeometry.folderPadding)
                    .offset(x: HomeGeometry.folderPadding, y: HomeGeometry.folderPadding)
                ForEach(folder.items.filter { $0.id != controller.draggedItem?.id }, id: \.id) { item in
                    let icon = folder.iconFrame(item).offsetBy(dx: -folder.drawingRect.minX, dy: -folder.drawingRect.minY)
                    AppIconImage(app: item.app, size: geo.iconSize).placed(icon)
                    if geo.showLabels && !item.title.isEmpty {
                        let w = geo.cellWidth - 2 * HomeGeometry.labelSideMargin
                        HomeLabel(title: item.title, width: w, onWallpaper: false)
                            .offset(x: icon.midX - w / 2, y: icon.maxY + HomeGeometry.labelSideMargin)
                    }
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .offset(x: rect.minX, y: rect.minY)
            .transition(.asymmetric(insertion: .scale(scale: 0.01), removal: .scale(scale: 0.2).combined(with: .opacity)))
        }
    }

    private var hintColor: Color { onWallpaper ? Color.white.opacity(0.5) : palette.textColor.opacity(0.5) }
    private var indicatorColor: Color { onWallpaper ? .white : palette.textColor }

    @ViewBuilder
    private func indicators(_ geo: HomeGeometry) -> some View {
        if controller.indicatorsAlpha > 0 {
            let count = controller.pageCount
            let r = HomeGeometry.pageIndicatorRadius, m = HomeGeometry.pageIndicatorMargin
            let required = CGFloat(count) * r * 2 + CGFloat(count) * (m - 1)
            let usable = geo.size.width - geo.left - geo.right
            let start = (usable - required) / 2 + geo.left
            let y = geo.pageIndicatorsYPos + geo.top + geo.iconMargin
            let step = r * 2 + m
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { page in
                    Circle().stroke(hintColor, lineWidth: 1)
                        .placed(CGRect(x: start + CGFloat(page) * step, y: y - r, width: 2 * r, height: 2 * r))
                }
                Circle().fill(indicatorColor)
                    .placed(CGRect(x: start + controller.pagePosition * step, y: y - r, width: 2 * r, height: 2 * r))
            }
            .opacity(controller.indicatorsAlpha)
        }
    }

    @ViewBuilder
    private func dragLayer(_ geo: HomeGeometry) -> some View {
        if let dragged = controller.draggedItem, let p = controller.dragPoint {
            ZStack(alignment: .topLeading) {
                if dragged.isSingleCellType {
                    let shadow = shadowCircleCenter(geo, p)
                    Circle().stroke(hintColor, lineWidth: 4)
                        .placed(CGRect(x: shadow.x - geo.iconSize / 2, y: shadow.y - geo.iconSize / 2,
                                       width: geo.iconSize, height: geo.iconSize))
                    // the icon itself, a bit above the finger to keep it visible
                    itemIcon(dragged, size: geo.iconSize)
                        .placed(CGRect(x: p.x - geo.iconSize / 1.5, y: p.y - geo.iconSize / 1.2, width: geo.iconSize, height: geo.iconSize))
                } else if dragged.type == .widget {
                    let rect = geo.widgetOccupiedRect(dragged, at: geo.closestCell(to: p))
                    let c = geo.cell(GridCell(x: rect.left, y: rect.top))
                    let w = CGFloat(dragged.widthInCells) * geo.cellWidth, h = CGFloat(dragged.heightInCells) * geo.cellHeight
                    RoundedRectangle(cornerRadius: HomeGeometry.roundedCornerRadius).stroke(hintColor, lineWidth: 4)
                        .placed(CGRect(x: c.minX + geo.left, y: c.minY + geo.top, width: w, height: h))
                    if let (_, kind) = WidgetRegistry.kind(dragged.className) {
                        kind.content(controller.widgetContext(dragged))
                            .frame(width: w, height: h)
                            .opacity(0.8)
                            .offset(x: p.x - w / 2, y: p.y - h / 3)
                    }
                }
            }
        }
    }

    /// Where the drop shadow circle goes: the folder slot or grid cell under the finger.
    private func shadowCircleCenter(_ geo: HomeGeometry, _ p: CGPoint) -> CGPoint {
        if let folder = controller.openFolder, folder.itemsDrawingRect.contains(p),
           let center = folder.itemsGridCenters.min(by: { abs($0.1.x - p.x) + abs($0.1.y - p.y) < abs($1.1.x - p.x) + abs($1.1.y - p.y) }) {
            let cellSize = folder.cellSize
            return CGPoint(x: center.1.x - cellSize / 2 + geo.iconMargin + geo.iconSize / 2,
                           y: center.1.y - cellSize / 2 + geo.iconMargin + geo.iconSize / 2)
        }
        let cell = geo.closestCell(to: p)
        let r = geo.cell(cell)
        let x = r.minX + geo.iconMargin + geo.iconSize / 2 + geo.left
        let y = (cell.y == geo.rowCount - 1 ? geo.cellHeight - geo.iconMargin - geo.iconSize / 2 : geo.iconMargin + geo.iconSize / 2)
            + geo.top + r.minY
        return CGPoint(x: x, y: y)
    }
}

/// MyAppWidgetHostView: the widget is interactive; its touches also feed the home screen's
/// gesture handling, so a long press opens the item menu and a horizontal swipe flips pages.
struct HomeWidgetView: View {
    let controller: HomeController
    let item: HomeGridItem
    let kind: HomeWidgetKind
    @State private var tracking = false

    var body: some View {
        kind.content(controller.widgetContext(item))
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("home"))
                    .onChanged { v in
                        if !tracking {
                            tracking = true
                            controller.touchBegan(v.startLocation)
                        }
                        controller.touchMoved(v.location)
                    }
                    .onEnded { v in
                        tracking = false
                        controller.touchEnded(v.location, velocity: CGVector(dx: v.velocity.width, dy: v.velocity.height))
                    }
            )
            .onDisappear {
                if tracking { controller.touchEnded(.zero, velocity: .zero, cancelled: true) }
            }
    }
}
