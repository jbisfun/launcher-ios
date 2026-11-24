import FossifyCommons
import SwiftUI

private struct MenuRow: Identifiable {
    let title: String
    let icon: String?
    let action: () -> Void
    var id: String { title }
}

/// The PopupMenus: menu_app_icon (long press on an item) and menu_home_screen (long press on
/// empty space). Tapping outside dismisses them; moving the finger after a long press starts a drag.
struct MenusOverlay: View {
    @Environment(\.palette) private var palette
    let controller: HomeController
    let size: CGSize

    var body: some View {
        if let req = controller.itemMenu {
            dismissLayer { controller.itemMenu = nil }
            menu(itemRows(req), anchor: req.anchor)
        } else if let p = controller.mainMenuAnchor {
            dismissLayer { controller.mainMenuAnchor = nil }
            menu(mainRows(), anchor: CGRect(x: p.x, y: p.y, width: 0, height: 0))
        }
    }

    private func dismissLayer(_ dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.001)
            .frame(width: size.width, height: size.height)
            .onTapGesture(perform: dismiss)
    }

    /// handleGridItemPopupMenu: which entries apply to the item (uninstalling a bundled app isn't possible).
    private func itemRows(_ req: ItemMenuRequest) -> [MenuRow] {
        let item = req.item
        let kind = item.type == .widget ? WidgetRegistry.kind(item.className)?.1 : nil
        var rows: [MenuRow] = []
        func add(_ title: String, _ icon: String, _ action: @escaping () -> Void) {
            rows.append(MenuRow(title: title, icon: icon) {
                controller.itemMenu = nil
                action()
            })
        }
        if item.type == .icon {
            add("App info", "info.circle") { controller.aboutApp = item.app }
        }
        if item.type == .icon && req.onAllApps {
            add("Hide icon", "eye.slash") { controller.hideIcon(item) }
        }
        if item.type == .widget && kind?.resizable == true {
            add("Resize", "arrow.up.left.and.arrow.down.right") { controller.widgetLongPressed(item) }
        }
        if item.type == .widget && kind?.configure != nil {
            add("Reconfigure", "gearshape") { controller.reconfigure(item) }
        }
        if (item.type == .icon || item.type == .folder) && !req.onAllApps {
            add("Rename", "pencil") { controller.renameItem(item) }
        }
        if !req.onAllApps {
            add("Remove", "xmark") { controller.removeAppIcon(item) }
        }
        return rows
    }

    private func mainRows() -> [MenuRow] {
        func row(_ title: String, _ action: @escaping () -> Void) -> MenuRow {
            MenuRow(title: title, icon: nil) {
                controller.mainMenuAnchor = nil
                action()
            }
        }
        return [
            row("Widgets") { controller.showWidgets() },
            row("Wallpapers") { controller.showWallpapers = true },
            row("Launcher settings") { controller.showSettings = true },
        ]
    }

    private func menu(_ rows: [MenuRow], anchor: CGRect) -> some View {
        let width: CGFloat = 220
        let rowHeight: CGFloat = 48
        let height = CGFloat(rows.count) * rowHeight + 16
        let x = min(max(anchor.midX - width / 2, 8), size.width - width - 8)
        let above = anchor.minY - height - 8
        let y = above > 40 ? above : min(anchor.maxY + 8, size.height - height - 8)
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                Button(action: row.action) {
                    HStack(spacing: 16) {
                        if let icon = row.icon {
                            Image(systemName: icon).font(.system(size: 17)).frame(width: 24)
                        }
                        Text(row.title).font(.system(size: 16))
                        Spacer()
                    }
                    .foregroundStyle(palette.textColor)
                    .padding(.horizontal, 16)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressedStyle())
            }
        }
        .padding(.vertical, 8)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface).shadow(radius: 8))
        .offset(x: x, y: y)
    }
}
