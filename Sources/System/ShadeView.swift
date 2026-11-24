import FossifyCommons
import MusicPlayerKit
import Observation
import SwiftUI
import UserNotifications

/// A delivered notification as the shade shows it.
struct ShadeNotification: Identifiable {
    let identifier: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// The bundled app that posted it (AppNotifications' identifier prefixes), nil if unknown.
    let app: BundledApp?
    var id: String { identifier }
}

/// NotificationEntryManager: the process' delivered notifications, grouped by app.
@MainActor
@Observable
final class ShadeNotifications {
    private(set) var items: [ShadeNotification] = []

    var groups: [(app: BundledApp?, items: [ShadeNotification])] {
        var order: [BundledApp?] = []
        var byApp: [BundledApp?: [ShadeNotification]] = [:]
        for n in items {
            if byApp[n.app] == nil { order.append(n.app) }
            byApp[n.app, default: []].append(n)
        }
        return order.map { ($0, byApp[$0] ?? []) }
    }

    func refresh() {
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let entries = delivered.map { n in
                let c = n.request.content
                return (n.request.identifier, c.title, c.subtitle, c.body, n.date)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    SystemUI.shared.notifications.items = entries
                        .map { ShadeNotification(identifier: $0.0, title: $0.1, subtitle: $0.2, body: $0.3, date: $0.4,
                                                 app: Self.owner(of: $0.0)) }
                        .sorted { $0.date > $1.date }
                }
            }
        }
    }

    /// AppNotifications maps request identifiers to NotificationHub app ids (the port minus "-ios").
    static func owner(of identifier: String) -> BundledApp? {
        guard let id = AppNotifications.owner(ofIdentifier: identifier) else { return nil }
        return BundledApp.allCases.first { $0.info.port == "\(id)-ios" || $0.rawValue == id }
    }

    func dismiss(_ n: ShadeNotification) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [n.identifier])
        items.removeAll { $0.identifier == n.identifier }
    }

    func clearAll() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        items.removeAll()
    }
}

/// NotificationShadeWindowView: pull down from the top edge for the quick quick settings (header +
/// 2x2 tiles) and the notifications, pull again (or drag the panel down) for the full paged
/// quick settings with the brightness slider; drag up / tap below / Back to close.
struct ShadeView: View {
    @Environment(\.palette) private var palette
    let size: CGSize
    private let ui = SystemUI.shared
    @State private var panelHeight: CGFloat = 320
    @State private var page = 0
    @State private var panelDrag: CGFloat = 0

    static func pullGesture(ui: SystemUI) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if !ui.shadeDragging {
                    ui.shadeDragging = true
                    ui.notifications.refresh()
                    ui.tiles.refresh()
                }
                let t = max(0, value.translation.height)
                ui.shadeOpen = min(1, t / 320)
                // pulled well past the panel: the full quick settings
                if t > 520 && !ui.qsExpanded { withAnimation(.easeOut(duration: 0.2)) { ui.qsExpanded = true } }
            }
            .onEnded { value in
                ui.shadeDragging = false
                let open = ui.shadeOpen > 0.35 || value.predictedEndTranslation.height > 260
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    ui.shadeOpen = open ? 1 : 0
                    if !open { ui.qsExpanded = false }
                }
                if open { ui.notifications.refresh() }
                ui.shadeSettled()
            }
    }

    var body: some View {
        let colors = ShadeColors(palette: palette)
        let open = ui.shadeOpen
        ZStack(alignment: .top) {
            if ui.isShadeVisible {
                // ScrimView
                Color.black.opacity(0.55 * Double(open))
                    .contentShape(Rectangle())
                    .onTapGesture { ui.closeShade() }
                    .gesture(DragGesture(minimumDistance: 10).onEnded { v in
                        if v.translation.height < -30 { ui.closeShade() }
                    })
                VStack(spacing: 8) {
                    panel(colors)
                        .background(GeometryReader { g in
                            Color.clear.onAppear { panelHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in panelHeight = h }
                        })
                    notificationsColumn(colors)
                }
                .offset(y: -(1 - open) * (panelHeight + 40) + min(0, panelDrag))
                .opacity(Double(min(1, open * 3)))
                if ui.editingTiles {
                    QSEditView(onClose: { ui.editingTiles = false })
                        .padding(.top, ui.rawInsets.top)
                        .padding(.bottom, ui.navInset)
                        .background(colors.panel)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.2), value: ui.editingTiles)
        .task(id: ui.isShadeVisible) {
            // new notifications show up while the shade is open
            while ui.isShadeVisible && !Task.isCancelled {
                ui.notifications.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: quick settings panel

    private func panel(_ colors: ShadeColors) -> some View {
        VStack(spacing: 12) {
            header(colors)
            if ui.qsExpanded {
                BrightnessSlider()
                pagedTiles
                footer(colors)
            } else {
                tileGrid(Array(LauncherConfig.shared.qsTiles.prefix(4)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, ui.rawInsets.top + 4)
        .padding(.bottom, 16)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                .fill(colors.panel)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .foregroundStyle(colors.text)
        .contentShape(Rectangle())
        // simultaneous: the tile pages keep their horizontal paging
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard abs(v.translation.height) > abs(v.translation.width) else { return }
                    panelDrag = ui.qsExpanded ? 0 : v.translation.height
                }
                .onEnded { v in
                    let dy = abs(v.translation.height) > abs(v.translation.width) ? v.translation.height : 0
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        panelDrag = 0
                        if dy > 40 && !ui.qsExpanded {
                            ui.qsExpanded = true
                        } else if dy < -40 {
                            if ui.qsExpanded { ui.qsExpanded = false } else { ui.closeShade() }
                        }
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: ui.qsExpanded)
    }

    /// ShadeHeader: clock and date (big when expanded), battery on the right.
    private func header(_ colors: ShadeColors) -> some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: ui.qsExpanded ? 34 : 18, weight: ui.qsExpanded ? .regular : .medium))
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 14))
                    .foregroundStyle(colors.secondary)
                Spacer()
                BatteryLabel().foregroundStyle(colors.secondary)
            }
        }
        .frame(minHeight: 40)
    }

    private func tileGrid(_ specs: [QSTileSpec]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(specs) { QSTileView(spec: $0) }
        }
    }

    /// PagedTileLayout: 2 columns x 4 rows per page.
    private var pagedTiles: some View {
        let tiles = LauncherConfig.shared.qsTiles
        let pages = stride(from: 0, to: tiles.count, by: 8).map { Array(tiles[$0..<min($0 + 8, tiles.count)]) }
        let rows = min(4, (tiles.count + 1) / 2)
        return TabView(selection: $page) {
            ForEach(pages.indices, id: \.self) { i in
                tileGrid(pages[i]).frame(maxHeight: .infinity, alignment: .top).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: CGFloat(rows) * 80)
        .onChange(of: pages.count) { _, n in if page >= n { page = max(0, n - 1) } }
    }

    /// FooterActionsView: page indicator, edit, settings.
    private func footer(_ colors: ShadeColors) -> some View {
        let count = (LauncherConfig.shared.qsTiles.count + 7) / 8
        return HStack(spacing: 8) {
            if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule().fill(colors.text.opacity(i == page ? 0.9 : 0.3))
                            .frame(width: i == page ? 16 : 6.4, height: 6.4)
                    }
                }
            }
            Spacer()
            footerButton("pencil", colors, label: "Edit") { ui.editingTiles = true }
            footerButton("gearshape.fill", colors, label: "Settings") { ui.openLauncherSettings() }
        }
        .frame(height: 48)
    }

    private func footerButton(_ icon: String, _ colors: ShadeColors, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 20).fill(colors.surface))
        }
        .accessibilityLabel(label)
    }

    // MARK: notifications

    private func notificationsColumn(_ colors: ShadeColors) -> some View {
        let groups = ui.notifications.groups
        return ScrollView {
            VStack(spacing: 8) {
                if MusicPlayerSession.isActive { MediaControlCard() }
                if groups.isEmpty {
                    Text("No notifications")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.vertical, 24)
                } else {
                    ForEach(groups, id: \.app?.rawValue) { group in
                        NotificationGroupCard(app: group.app, items: group.items, colors: colors)
                    }
                    HStack {
                        Spacer()
                        Button { withAnimation { ui.notifications.clearAll() } } label: {
                            Text("Clear all").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(colors.text)
                                .padding(.horizontal, 18).frame(height: 40)
                                .background(Capsule().fill(colors.card))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, ui.navInset + 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: max(0, size.height - panelHeight - 8))
        .fixedSize(horizontal: false, vertical: groups.isEmpty && !MusicPlayerSession.isActive)
    }
}

/// The battery meter of the shade header (UIDevice's level and charging state are readable).
private struct BatteryLabel: View {
    @State private var level: Float = UIDevice.current.batteryLevel
    @State private var charging = false

    var body: some View {
        HStack(spacing: 4) {
            if level >= 0 { Text("\(Int((level * 100).rounded()))%").font(.system(size: 14)) }
            Image(systemName: icon).font(.system(size: 15))
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in update() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in update() }
    }

    private var icon: String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<0: return "battery.100"
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func update() {
        level = UIDevice.current.batteryLevel
        charging = [.charging, .full].contains(UIDevice.current.batteryState)
    }
}

/// An app's notifications as one AOSP group card (notification_corner_radius 28dp): the app
/// header, then each notification; swipe one sideways to dismiss it, tap to open the app.
private struct NotificationGroupCard: View {
    let app: BundledApp?
    let items: [ShadeNotification]
    let colors: ShadeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, n in
                if index > 0 { Divider().overlay(colors.secondary.opacity(0.25)).padding(.leading, 56) }
                NotificationRow(app: app, notification: n, colors: colors, showHeader: index == 0)
            }
        }
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(colors.card))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct NotificationRow: View {
    let app: BundledApp?
    let notification: ShadeNotification
    let colors: ShadeColors
    let showHeader: Bool
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconImage(app: app, size: 32)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .opacity(showHeader ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                if showHeader {
                    HStack(spacing: 4) {
                        Text(app?.info.name ?? "Fossify")
                        Text("•")
                        Text(relative(notification.date))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(colors.secondary)
                }
                if !notification.title.isEmpty {
                    Text(notification.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                }
                if !notification.subtitle.isEmpty {
                    Text(notification.subtitle).font(.system(size: 14)).lineLimit(1)
                }
                if !notification.body.isEmpty {
                    Text(notification.body).font(.system(size: 14)).foregroundStyle(colors.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(colors.card)
        .offset(x: dx)
        .opacity(Double(1 - min(1, abs(dx) / 300)))
        .contentShape(Rectangle())
        .onTapGesture { SystemUI.shared.open(notification) }
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { dx = v.translation.width } }
                .onEnded { v in
                    if abs(v.translation.width) > 110 || abs(v.predictedEndTranslation.width) > 260 {
                        withAnimation(.easeIn(duration: 0.15)) { dx = v.translation.width > 0 ? 500 : -500 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { SystemUI.shared.notifications.dismiss(notification) }
                        }
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { dx = 0 }
                    }
                }
        )
    }

    private func relative(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}
