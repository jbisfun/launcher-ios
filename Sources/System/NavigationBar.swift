import FossifyCommons
import SwiftUI
import UIKit

// res/drawable/ic_sysbar_back.xml, ic_sysbar_home.xml, ic_sysbar_recent.xml (20x20 viewport).

struct SysbarBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(15.5417, 1.66669))
        path.addCurve(to: p(14.5333, 1.94169), control1: p(15.1833, 1.66669), control2: p(14.8417, 1.76669))
        path.addLine(to: p(3.21667, 8.74169))
        path.addCurve(to: p(2.5, 10), control1: p(2.775, 9.00002), control2: p(2.5, 9.48335))
        path.addCurve(to: p(3.21667, 11.2584), control1: p(2.5, 10.5167), control2: p(2.775, 11))
        path.addLine(to: p(14.5333, 18.05))
        path.addCurve(to: p(15.5417, 18.325), control1: p(14.8417, 18.2334), control2: p(15.1833, 18.325))
        path.addCurve(to: p(17.5, 16.3667), control1: p(16.625, 18.325), control2: p(17.5, 17.45))
        path.addLine(to: p(17.5, 3.62502))
        path.addCurve(to: p(15.5417, 1.66669), control1: p(17.5, 2.54169), control2: p(16.625, 1.66669))
        path.closeSubpath()
        return path
    }
}

struct SysbarHomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20
        let r = 8.33333 * s
        let c = CGPoint(x: rect.minX + 10 * s, y: rect.minY + 10 * s)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

struct SysbarRecentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20
        let r = CGRect(x: rect.minX + 2.5 * s, y: rect.minY + 2.5 * s, width: 15 * s, height: 15 * s)
        return Path(roundedRect: r, cornerRadius: 1.976 * s)
    }
}

/// NavigationBarView / NavigationBarInflaterView: config_navBarLayout
/// "left[.5W],back[1WC];home;recent[1WC],right[.5W]" with 70dp keys and 20dp icons, or the gesture
/// navigation handle (108x4dp, 10dp above the bottom).
struct NavigationBarView: View {
    @Environment(\.palette) private var palette
    private let ui = SystemUI.shared

    var body: some View {
        let style = ui.navBarStyle(palette)
        // light_mode_icon_color_single_tone / dark_mode_icon_color_single_tone
        let tint = style.light ? Color.white : Color.black.opacity(0.6)
        ZStack {
            (style.background ?? .clear)
            if ui.navMode == .threeButton {
                HStack(spacing: 0) {
                    Color.clear.frame(width: SystemUI.navKeyWidth / 2)
                    NavKey(label: "Back", tint: tint, light: style.light, action: ui.back) { SysbarBackShape() }
                    Spacer(minLength: 0)
                    NavKey(label: "Home", tint: tint, light: style.light, action: ui.goHome) { SysbarHomeShape() }
                    Spacer(minLength: 0)
                    NavKey(label: "Overview", tint: tint, light: style.light, action: ui.toggleRecents) { SysbarRecentShape() }
                    Color.clear.frame(width: SystemUI.navKeyWidth / 2)
                }
                .frame(height: SystemUI.navBarHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                GestureHandle(light: style.light)
            }
        }
        .animation(.easeOut(duration: 0.15), value: style.light)
    }
}

private struct NavKey<Icon: Shape>: View {
    let label: String
    let tint: Color
    let light: Bool
    let action: () -> Void
    let icon: () -> Icon

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            icon().fill(tint)
                .frame(width: 20, height: 20)
                .frame(width: SystemUI.navKeyWidth, height: SystemUI.navBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyRippleStyle(light: light))
        .accessibilityLabel(label)
    }
}

/// KeyButtonRipple: a round highlight behind the pressed key.
private struct KeyRippleStyle: ButtonStyle {
    let light: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill((light ? Color.white : Color.black).opacity(configuration.isPressed ? 0.2 : 0))
                    .frame(width: 44, height: 44)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// NavigationHandle + the quickstep swipe: up = home, up and hold = overview.
private struct GestureHandle: View {
    let light: Bool
    private let ui = SystemUI.shared
    @State private var holdWork: DispatchWorkItem?
    @State private var openedRecents = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.contentShape(Rectangle())
            // navigation_bar_home_handle_light_color / dark_color
            Capsule()
                .fill(light ? Color.white.opacity(0.92) : Color.black.opacity(0.6))
                .frame(width: 108, height: 4)
                .padding(.bottom, 10)
                .offset(y: -ui.homeGestureProgress * 24)
        }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    let up = max(0, -value.translation.height)
                    ui.homeGestureProgress = min(1, up / 240)
                    ui.applyHomeGestureFeedback()
                    // swipe up and hold: the overview opens when the finger pauses
                    holdWork?.cancel()
                    if up > 60 && !openedRecents && !ui.recentsVisible {
                        let work = DispatchWorkItem {
                            openedRecents = true
                            ui.homeGestureProgress = 0
                            ui.applyHomeGestureFeedback()
                            ui.toggleRecents()
                        }
                        holdWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                    }
                }
                .onEnded { value in
                    holdWork?.cancel()
                    holdWork = nil
                    let up = -value.translation.height
                    let fling = -value.predictedEndTranslation.height
                    ui.homeGestureProgress = 0
                    ui.applyHomeGestureFeedback()
                    if !openedRecents && (up > 40 || fling > 120) { ui.goHome() }
                    openedRecents = false
                }
        )
    }
}

/// EdgeBackGestureHandler: a swipe in from either edge is Back, with the NavigationBarEdgePanel arrow.
struct BackGestureEdges: View {
    let size: CGSize
    private let ui = SystemUI.shared
    /// config_backGestureThreshold-ish: how far to pull before releasing triggers Back.
    private let threshold: CGFloat = 64

    var body: some View {
        let top = ui.topStrip, bottom = ui.navInset
        let height = max(0, size.height - top - bottom)
        ZStack(alignment: .topLeading) {
            edge(fromLeft: true).frame(width: SystemUI.backGestureInset, height: height).offset(y: top)
            edge(fromLeft: false).frame(width: SystemUI.backGestureInset, height: height)
                .offset(x: size.width - SystemUI.backGestureInset, y: top)
            if let g = ui.backGesture {
                arrow(g)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    private func edge(fromLeft: Bool) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        let d = fromLeft ? value.translation.width : -value.translation.width
                        ui.backGesture = BackGestureState(fromLeft: fromLeft, y: value.location.y, distance: max(0, d))
                    }
                    .onEnded { value in
                        let d = fromLeft ? value.translation.width : -value.translation.width
                        withAnimation(.easeOut(duration: 0.15)) { ui.backGesture = nil }
                        if d > threshold {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            ui.back()
                        }
                    }
            )
    }

    private func arrow(_ g: BackGestureState) -> some View {
        let progress = min(1, g.distance / threshold)
        let travel = min(g.distance, threshold * 1.3) * 0.5
        let x = g.fromLeft ? travel - 8 : size.width - travel - 40
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55 * progress))
                .frame(width: 48, height: 48)
            Image(systemName: g.fromLeft ? "chevron.left" : "chevron.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(progress))
        }
        .scaleEffect(0.7 + 0.3 * progress)
        .offset(x: x, y: g.y - 24)
        .allowsHitTesting(false)
    }
}

extension SystemUI {
    /// The foreground app shrinks while swiping up from the handle.
    func applyHomeGestureFeedback() {
        guard let window = foreground?.window else { return }
        let scale = 1 - homeGestureProgress * 0.12
        window.transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: 0, y: -homeGestureProgress * 60)
    }
}
