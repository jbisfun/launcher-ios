import FossifyCommons
import SwiftUI

private struct ScrollTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Bottom sheet chrome shared by the app drawer and the widgets list (setupDrawerBackground),
/// pulled down to close when its list is scrolled to the top (onInterceptTouchEvent).
struct DrawerSheet<Content: View>: View {
    @Environment(\.palette) private var palette
    let controller: HomeController
    let widgets: Bool
    @Binding var atTop: Bool
    @ViewBuilder let content: () -> Content
    @State private var pulling = false

    var body: some View {
        // the home screen ignores the safe area, so the sheet pads for the status bar itself
        content()
            .padding(.top, controller.geo?.top ?? 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                    .fill(palette.backgroundColor)
                    .ignoresSafeArea()
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { v in
                        if !pulling && atTop && v.translation.height > 0 && abs(v.translation.height) > abs(v.translation.width) {
                            pulling = true
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        if pulling { controller.dragDrawer(widgets: widgets, by: v.translation.height) }
                    }
                    .onEnded { v in
                        guard pulling else { return }
                        pulling = false
                        controller.releaseDrawer(widgets: widgets, flingDown: v.velocity.height > 800)
                    }
            )
    }
}

/// A drawer search field (MySearchMenu without its toolbar).
struct DrawerSearchBar: View {
    @Environment(\.palette) private var palette
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.secondaryText)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(palette.secondaryText))
                .focused(focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark").foregroundStyle(palette.secondaryText) }
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Capsule().fill(palette.surface))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// AllAppsFragment: search bar, the apps in a grid with a fast scroller.
struct AllAppsView: View {
    @Environment(\.palette) private var palette
    @Bindable var controller: HomeController
    @FocusState private var searchFocused: Bool
    @State private var atTop = true
    @State private var topID: String?

    private var config: LauncherConfig { controller.config }

    private var filtered: [AppLauncher] {
        let launchers = controller.store.launchers
        let q = controller.allAppsQuery.launcherNormalized
        return q.isEmpty ? launchers : launchers.filter { $0.title.launcherNormalized.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        DrawerSheet(controller: controller, widgets: false, atTop: $atTop) {
            VStack(spacing: 0) {
                if config.showSearchBar {
                    DrawerSearchBar(placeholder: "Search", text: $controller.allAppsQuery, focused: $searchFocused) {
                        // IME_ACTION_GO launches the first result
                        if let first = filtered.first { launch(first) }
                    }
                } else {
                    Color.clear.frame(height: 16)
                }
                let apps = filtered
                if apps.isEmpty {
                    Text("No items found").foregroundStyle(palette.secondaryText).padding(.top, 32)
                    Spacer()
                } else {
                    grid(apps)
                }
            }
        }
        .onChange(of: controller.searchFocusRequest) { searchFocused = true }
        .onChange(of: controller.drawerResetRequest) {
            searchFocused = false
            topID = filtered.first?.id
        }
    }

    private func grid(_ apps: [AppLauncher]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, config.drawerColumnCount))
        return GeometryReader { geo in
            let iconWidth = geo.size.width / CGFloat(max(1, config.drawerColumnCount))
            let padding = iconWidth * 0.1
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(apps) { launcher in
                        cell(launcher, iconSize: min(iconWidth - 2 * padding, 64))
                            .id(launcher.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 24 + (controller.geo?.bottom ?? 0))
                .background(GeometryReader { g in
                    Color.clear.preference(key: ScrollTopKey.self, value: g.frame(in: .named("allApps")).minY)
                })
            }
            .coordinateSpace(name: "allApps")
            .scrollPosition(id: $topID, anchor: .top)
            .scrollDismissesKeyboard(.immediately)
            .onPreferenceChange(ScrollTopKey.self) { atTop = $0 >= -1 }
            .overlay(alignment: .trailing) {
                FastScroller(count: apps.count, position: apps.firstIndex { $0.id == topID } ?? 0,
                             bubbleText: { apps.indices.contains($0) ? String(apps[$0].bubbleText.prefix(1)).uppercased() : "" },
                             onScroll: { i in if apps.indices.contains(i) { topID = apps[i].id } })
            }
        }
    }

    private func cell(_ launcher: AppLauncher, iconSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            AppIconImage(app: launcher.app, size: iconSize)
            if config.showDrawerAppLabels {
                Text(launcher.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textColor)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .frame(height: iconSize + (config.showDrawerAppLabels ? 48 : 16))
        .overlay {
            TouchCatcher(onTap: { launch(launcher) }, onLongPress: { state, p, frame in
                switch state {
                case .began:
                    searchFocused = false
                    let iconRect = CGRect(x: frame.midX - iconSize / 2, y: frame.minY + 8, width: iconSize, height: iconSize)
                    controller.drawerItemLongPressed(launcher, at: p, iconRect: iconRect)
                    // closeSearch()
                    controller.allAppsQuery = ""
                case .changed: controller.touchMoved(p)
                case .ended: controller.touchEnded(p, velocity: .zero)
                case .cancelled, .failed: controller.touchEnded(p, velocity: .zero, cancelled: true)
                default: break
                }
            })
        }
    }

    private func launch(_ launcher: AppLauncher) {
        controller.launch(launcher.app, nil)
        if config.closeAppDrawer { controller.closeAppDrawer(delayed: true) }
    }
}
