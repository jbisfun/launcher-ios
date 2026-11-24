import SwiftUI

/// MyAppWidgetResizeFrame: drag a side of the frame to resize the widget, snapping to free cells.
struct WidgetResizeFrame: View {
    private enum Direction { case none, left, top, right, bottom }

    let controller: HomeController
    let item: HomeGridItem
    let geo: HomeGeometry

    @State private var frameRect: CGRect = .zero
    @State private var cells = (left: 0, top: 0, right: 0, bottom: 0)
    @State private var direction = Direction.none
    @State private var downAt = Date()
    @State private var occupied = Set<GridCell>()
    @State private var started = false

    private static let dotRadius: CGFloat = 8
    private static let maxTouchLineDistance = dotRadius * 5

    private var minWidthCells: Int {
        min(geo.columnCount, Int(WidgetRegistry.kind(item.className)?.1.minSize.width.rounded() ?? 1))
    }
    private var minHeightCells: Int {
        min(geo.rowCount, Int(WidgetRegistry.kind(item.className)?.1.minSize.height.rounded() ?? 1))
    }

    var body: some View {
        let r = Self.dotRadius
        ZStack {
            Rectangle().stroke(Color.white, lineWidth: 2).padding(r)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ForEach(0..<4, id: \.self) { i in
                    let center = [CGPoint(x: r, y: h / 2), CGPoint(x: w / 2, y: r), CGPoint(x: w - r, y: h / 2), CGPoint(x: w / 2, y: h - r)][i]
                    Circle().fill(Color.white).frame(width: 2 * r, height: 2 * r).position(center)
                }
            }
        }
        .contentShape(Rectangle())
        .placed(frameRect)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("home"))
                .onChanged { v in
                    if !started {
                        started = true
                        down(v.startLocation)
                    }
                    move(v.location)
                }
                .onEnded { _ in
                    started = false
                    up()
                }
        )
        .onAppear {
            frameRect = geo.widgetFrame(item)
            cells = (item.left, item.top, item.right, item.bottom)
            if let id = item.id { occupied = controller.occupiedCells(excluding: id) }
        }
    }

    private func down(_ p: CGPoint) {
        downAt = Date()
        let x = p.x - frameRect.minX, y = p.y - frameRect.minY
        let d = Self.maxTouchLineDistance
        if x < d {
            direction = .left
        } else if y < d {
            direction = .top
        } else if x > frameRect.width - d {
            direction = .right
        } else if y > frameRect.height - d {
            direction = .bottom
        } else {
            direction = .none
        }
    }

    private func roundToClosestMultiply(_ value: CGFloat, _ number: CGFloat) -> CGFloat {
        number * abs(value / number).rounded()
    }

    private func free(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>) -> Bool {
        for x in xs { for y in ys where occupied.contains(GridCell(x: x, y: y)) { return false } }
        return true
    }

    private func range(_ a: Int, _ b: Int) -> ClosedRange<Int> { min(a, b)...max(a, b) }

    private func move(_ p: CGPoint) {
        let minWidth = CGFloat(minWidthCells) * geo.cellWidth
        let minHeight = CGFloat(minHeightCells) * geo.cellHeight
        var f = frameRect
        switch direction {
        case .left:
            let wantedLeft = f.maxX - p.x >= minWidth ? p.x : f.maxX - minWidth
            let cellX = Int(roundToClosestMultiply(wantedLeft - geo.left, geo.cellWidth) / geo.cellWidth)
            if free(range(cellX, cells.right), range(cells.top, cells.bottom)) && cells.left != cellX && cellX >= 0 {
                cells.left = cellX
                changed()
            }
            f = CGRect(x: wantedLeft, y: f.minY, width: f.maxX - wantedLeft, height: f.height)
        case .top:
            let wantedTop = f.maxY - p.y >= minHeight ? p.y : f.maxY - minHeight
            let cellY = Int(roundToClosestMultiply(wantedTop - geo.top, geo.cellHeight) / geo.cellHeight)
            if free(range(cells.left, cells.right), range(cellY, cells.bottom)) && cells.top != cellY && cellY >= 0 {
                cells.top = cellY
                changed()
            }
            f = CGRect(x: f.minX, y: wantedTop, width: f.width, height: f.maxY - wantedTop)
        case .right:
            let wantedRight = p.x - f.minX >= minWidth ? p.x : f.minX + minWidth
            let cellX = Int(roundToClosestMultiply(wantedRight - geo.left, geo.cellWidth) / geo.cellWidth) - 1
            if free(range(cells.left, cellX), range(cells.top, cells.bottom)) && cells.right != cellX && cellX < geo.columnCount {
                cells.right = cellX
                changed()
            }
            f.size.width = wantedRight - f.minX
        case .bottom:
            let wantedBottom = p.y - f.minY >= minHeight ? p.y : f.minY + minHeight
            let cellY = Int(roundToClosestMultiply(wantedBottom - geo.top, geo.cellHeight) / geo.cellHeight) - 1
            var ok = free(range(cells.left, cells.right), range(cells.top, cellY))
            if cellY >= geo.rowCount - 1 { ok = false }
            if ok && cells.bottom != cellY {
                cells.bottom = cellY
                changed()
            }
            f.size.height = wantedBottom - f.minY
        case .none:
            return
        }
        frameRect = f
    }

    private func up() {
        if direction == .none || Date().timeIntervalSince(downAt) < 0.15 {
            // MAX_CLICK_DURATION: a click hides the frame
            controller.hideResizeLines()
            direction = .none
            return
        }
        // snap the frame to the widget's cells
        var snapped = item
        (snapped.left, snapped.top, snapped.right, snapped.bottom) = cells
        let target = geo.widgetFrame(snapped)
        withAnimation(.easeOut(duration: 0.15)) { frameRect = target }
        direction = .none
    }

    private func changed() {
        if let id = item.id { controller.resizeWidget(id, to: cells) }
    }
}
