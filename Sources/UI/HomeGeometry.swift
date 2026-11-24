import SwiftUI

/// HomeScreenGrid's measurements (fillCellSizes, getClickableRect, calculateWidgetPos, ...),
/// in points of the full-screen home view. The last row is the dock.
struct HomeGeometry: Equatable {
    static let labelSideMargin: CGFloat = 4       // small_margin
    static let labelFontSize: CGFloat = 12        // smaller_text_size
    static let folderPadding: CGFloat = 8         // medium_margin
    static let folderTitleFontSize: CGFloat = 16  // medium_text_size
    static let roundedCornerRadius: CGFloat = 16  // activity_margin
    static let pageIndicatorRadius: CGFloat = 6
    static let pageIndicatorMargin: CGFloat = 6

    let size: CGSize
    let rowCount: Int
    let columnCount: Int
    let showLabels: Bool
    /// sideMargins: normal_margin plus the system bars / cutouts.
    let left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let extraXMargin: CGFloat
    let extraYMargin: CGFloat
    let iconMargin: CGFloat
    let iconSize: CGFloat
    let dockCellY: CGFloat
    let pageIndicatorsYPos: CGFloat

    init(size: CGSize, insets: EdgeInsets, rows: Int, columns: Int, showLabels: Bool) {
        self.size = size
        rowCount = rows
        columnCount = columns
        self.showLabels = showLabels
        let sideMargin: CGFloat = 12
        left = sideMargin + insets.leading
        right = sideMargin + insets.trailing
        top = insets.top
        bottom = insets.bottom
        let fakeWidth = size.width - left - right
        let fakeHeight = size.height - top - bottom
        cellWidth = floor(fakeWidth / CGFloat(columns))
        cellHeight = floor(fakeHeight / CGFloat(rows))
        extraXMargin = cellWidth > cellHeight ? floor((cellWidth - cellHeight) / 2) : 0
        extraYMargin = cellHeight > cellWidth ? floor((cellHeight - cellWidth) / 2) : 0
        iconMargin = floor(10 * 5 / CGFloat(columns))
        iconSize = min(cellWidth, cellHeight) - 2 * iconMargin
        pageIndicatorsYPos = CGFloat(rows - 1) * cellHeight + extraYMargin
        dockCellY = CGFloat(rows - 1) * cellHeight
    }

    /// Height of two label lines: every item gets the same clickable area.
    var labelHeight: CGFloat { ceil(UIFont.systemFont(ofSize: Self.labelFontSize).lineHeight * 2) }

    /// The cell rect in grid space (without side margins).
    func cell(_ c: GridCell) -> CGRect {
        let yMargin = c.y == rowCount - 1 ? 0 : extraYMargin
        return CGRect(x: CGFloat(c.x) * cellWidth + extraXMargin, y: CGFloat(c.y) * cellHeight + yMargin,
                      width: cellWidth - 2 * extraXMargin, height: cellHeight - 2 * yMargin)
    }

    var allCells: [GridCell] {
        (0..<columnCount).flatMap { x in (0..<rowCount).map { GridCell(x: x, y: $0) } }
    }

    /// gridCenters.minBy { manhattan distance } + getClosestGridCells.
    func closestCell(to p: CGPoint) -> GridCell {
        allCells.min { a, b in
            let ca = cell(a), cb = cell(b)
            return abs(ca.midX - p.x + left) + abs(ca.midY - p.y + top) < abs(cb.midX - p.x + left) + abs(cb.midY - p.y + top)
        } ?? GridCell(x: 0, y: 0)
    }

    /// Where a top-level icon or folder is drawn on its page (page offset not applied).
    func iconFrame(_ item: HomeGridItem) -> CGRect {
        let c = cell(item.topLeft(rowCount))
        let x = c.minX + iconMargin + left
        let y = item.docked ? dockCellY + cellHeight - iconMargin - iconSize + top : c.minY + iconMargin + top
        return CGRect(x: x, y: y, width: iconSize, height: iconSize)
    }

    /// getClickableRect: the icon with its margins and, off the dock, its label.
    func clickableRect(_ item: HomeGridItem) -> CGRect {
        let c = cell(item.topLeft(rowCount))
        let clickableLeft = c.minX + left
        let clickableTop = (item.docked ? dockCellY + cellHeight - iconSize - iconMargin : c.minY - iconMargin) + top
        let additional = !item.docked && showLabels ? labelHeight : 0
        return CGRect(x: clickableLeft, y: clickableTop, width: iconSize + 2 * iconMargin,
                      height: iconSize + 2 * iconMargin + additional)
    }

    /// calculateWidgetPos + updateWidgetPositionAndSize.
    func widgetFrame(_ item: HomeGridItem) -> CGRect {
        let c = cell(item.topLeft(rowCount))
        return CGRect(x: c.minX + left, y: c.minY + top, width: CGFloat(item.widthInCells) * cellWidth,
                      height: CGFloat(item.heightInCells) * cellHeight)
    }

    /// getWidgetOccupiedRect: drag the center of the widget, not its top left corner.
    func widgetOccupiedRect(_ item: HomeGridItem, at c: GridCell) -> (left: Int, top: Int, right: Int, bottom: Int) {
        var l = c.x - Int(floor(Double(item.widthInCells - 1) / 2))
        var r = l + item.widthInCells - 1
        var t = c.y
        var b = t + item.heightInCells - 1
        if l < 0 {
            r -= l
            l = 0
        } else if r > columnCount - 1 {
            let diff = r - columnCount + 1
            r -= diff
            l -= diff
        }
        if t < 0 {
            b -= t
            t = 0
        } else if b > rowCount - 2 {
            let diff = b - rowCount + 2
            b -= diff
            t -= diff
        }
        return (l, t, r, b)
    }

    func outOfBounds(_ item: HomeGridItem) -> Bool {
        item.left >= columnCount || item.right >= columnCount
            || (!item.docked && (item.top >= rowCount - 1 || item.bottom >= rowCount - 1))
            || (item.type == .widget && (item.bottom - item.top > rowCount - 1 || item.right - item.left > columnCount - 1))
    }
}

/// HomeScreenFolder: the open folder's dialog and the positions of its items.
struct FolderLayout {
    let folder: HomeGridItem
    let items: [HomeGridItem]
    let geo: HomeGeometry

    var count: Int { items.count }
    var columns: Int { max(1, Int(ceil(sqrt(Double(count))))) }
    var rows: Int { max(1, Int(ceil(Double(count) / Double(columns)))) }
    var cellSize: CGFloat { min(geo.cellWidth, geo.cellHeight) }
    var gap: CGFloat { cellSize == geo.cellWidth ? 0 : cellSize / 5 }
    var yGap: CGFloat {
        geo.showLabels ? gap + HomeGeometry.labelFontSize + 2 * HomeGeometry.labelSideMargin : gap
    }

    /// getDrawingRect, on the folder's own page.
    var drawingRect: CGRect {
        guard count > 0 else { return .zero }
        let c = geo.cell(folder.topLeft(geo.rowCount))
        let centerX = geo.left + c.midX
        let centerY = geo.top + c.midY
        let p = HomeGeometry.folderPadding
        let width = CGFloat(columns) * cellSize + 2 * p + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * cellSize + 3 * p + HomeGeometry.folderTitleFontSize + CGFloat(rows) * yGap
        var top = centerY - height / 2
        var left = centerX - width / 2
        if left < geo.left { left = geo.left }
        if left + width > geo.size.width - geo.right { left -= left + width - (geo.size.width - geo.right) }
        if top < geo.top { top = geo.top }
        if top + height > geo.size.height - geo.bottom { top -= top + height - (geo.size.height - geo.bottom) }
        return CGRect(x: left, y: top, width: width, height: height)
    }

    var itemsDrawingRect: CGRect {
        let r = drawingRect
        let p = HomeGeometry.folderPadding
        return CGRect(x: r.minX + p, y: r.minY + 2 * p + HomeGeometry.folderTitleFontSize,
                      width: r.width - 2 * p, height: r.height - 3 * p - HomeGeometry.folderTitleFontSize)
    }

    /// getItemsGridCenters: (index, center).
    var itemsGridCenters: [(Int, CGPoint)] {
        guard count > 0 else { return [] }
        let r = itemsDrawingRect
        return (0..<(columns * rows)).map { index in
            let x = CGFloat(index % columns), y = CGFloat(index / columns)
            return (index, CGPoint(x: r.minX + x * cellSize + x * gap + cellSize / 2,
                                   y: r.minY + y * cellSize + y * yGap + cellSize / 2))
        }
    }

    func position(_ item: HomeGridItem) -> (row: Int, column: Int) {
        (item.left / columns, item.left % columns)
    }

    func itemRect(_ item: HomeGridItem) -> CGRect {
        let (row, column) = position(item)
        let r = itemsDrawingRect
        return CGRect(x: (r.minX + CGFloat(column) * cellSize + CGFloat(column) * gap).rounded(),
                      y: (r.minY + CGFloat(row) * cellSize + CGFloat(row) * yGap).rounded(),
                      width: cellSize, height: cellSize)
    }

    /// The icon of an item in the folder dialog.
    func iconFrame(_ item: HomeGridItem) -> CGRect {
        let r = itemRect(item)
        return CGRect(x: r.minX + geo.iconMargin, y: r.minY + geo.iconMargin, width: geo.iconSize, height: geo.iconSize)
    }

    func clickableRect(_ item: HomeGridItem) -> CGRect {
        let r = itemRect(item)
        let additional = geo.showLabels ? geo.labelHeight : 0
        return CGRect(x: r.minX, y: r.minY - geo.iconMargin, width: geo.iconSize + 2 * geo.iconMargin,
                      height: geo.iconSize + 2 * geo.iconMargin + additional)
    }
}
