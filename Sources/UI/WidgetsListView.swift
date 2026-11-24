import FossifyCommons
import SwiftUI

private struct WidgetsTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// WidgetsFragment: the bundled apps' widgets grouped by app (WidgetsListSection +
/// WidgetsListItemsHolder), searchable; long press one and drag it onto the home screen.
struct WidgetsListView: View {
    @Environment(\.palette) private var palette
    @Bindable var controller: HomeController
    @FocusState private var searchFocused: Bool
    @State private var atTop = true

    /// splitWidgetsByApps(), filtered by app or widget title.
    private var sections: [(BundledApp, [HomeWidgetKind])] {
        let q = controller.widgetsQuery.launcherNormalized
        return widgetProviders
            .sorted { $0.0.info.name < $1.0.info.name }
            .map { app, kinds in
                (app, q.isEmpty || app.info.name.launcherNormalized.localizedCaseInsensitiveContains(q)
                    ? kinds : kinds.filter { $0.title.launcherNormalized.localizedCaseInsensitiveContains(q) })
            }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        DrawerSheet(controller: controller, widgets: true, atTop: $atTop) {
            VStack(spacing: 0) {
                DrawerSearchBar(placeholder: "Search", text: $controller.widgetsQuery, focused: $searchFocused)
                let sections = sections
                if sections.isEmpty {
                    Text("No items found").foregroundStyle(palette.secondaryText).padding(.top, 32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sections, id: \.0) { app, kinds in
                                HStack(spacing: 12) {
                                    AppIconImage(app: app, size: 32)
                                    Text(app.info.name).font(.system(size: 16, weight: .medium)).foregroundStyle(palette.textColor)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 16) {
                                        ForEach(kinds) { kind in preview(app, kind) }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.bottom, 32 + (controller.geo?.bottom ?? 0))
                        .background(GeometryReader { g in
                            Color.clear.preference(key: WidgetsTopKey.self, value: g.frame(in: .named("widgetsList")).minY)
                        })
                    }
                    .coordinateSpace(name: "widgetsList")
                    .scrollDismissesKeyboard(.immediately)
                    .onPreferenceChange(WidgetsTopKey.self) { atTop = $0 >= -1 }
                }
            }
        }
    }

    /// item_widget_preview: the widget drawn small (its preview image), its title and size in cells.
    private func preview(_ app: BundledApp, _ kind: HomeWidgetKind) -> some View {
        let box: CGFloat = 140
        let geo = controller.geo
        let w = max(1, kind.defaultSize.width), h = max(1, kind.defaultSize.height)
        let fullW = w * (geo?.cellWidth ?? 70), fullH = h * (geo?.cellHeight ?? 90)
        let scale = min(box / fullW, box / fullH, 1)
        let item = HomeGridItem(id: nil, left: -1, top: -1, right: -1, bottom: -1, page: 0, packageName: app.rawValue, title: "",
                                type: .widget, className: kind.id, widthCells: Int(w), heightCells: Int(h))
        return VStack(spacing: 6) {
            kind.content(controller.widgetContext(item))
                .frame(width: fullW, height: fullH)
                .scaleEffect(scale)
                .frame(width: box, height: box)
                .allowsHitTesting(false)
                .overlay {
                    TouchCatcher(onTap: { controller.toast = "Long press the widget and drag it on your home screen" },
                                 onLongPress: { state, p, _ in
                                     switch state {
                                     case .began:
                                         searchFocused = false
                                         controller.widgetLongPressedOnList(app, kind, at: p)
                                     case .changed: controller.touchMoved(p)
                                     case .ended: controller.touchEnded(p, velocity: .zero)
                                     case .cancelled, .failed: controller.touchEnded(p, velocity: .zero, cancelled: true)
                                     default: break
                                     }
                                 })
                }
            Text(kind.title).font(.system(size: 14)).foregroundStyle(palette.textColor).lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(Int(w)) x \(Int(h))").font(.system(size: 12)).foregroundStyle(palette.secondaryText)
        }
        .frame(width: box)
    }
}
