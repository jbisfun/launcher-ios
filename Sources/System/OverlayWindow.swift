import SwiftUI
import UIKit

/// The system UI's window (status bar strip, navigation bar, shade, recents) above every app
/// window. Touches outside the system UI fall through to the windows below; it never becomes key,
/// so the keyboard keeps typing into the app.
final class OverlayWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let handles = MainActor.assumeIsolated { SystemUI.shared.overlayHandles(point) }
        guard handles else { return nil }
        return super.hitTest(point, with: event)
    }
}

final class OverlayController: UIHostingController<AnyView> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let window = view.window { SystemUI.shared.layoutChanged(window) }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let window = view.window { SystemUI.shared.layoutChanged(window) }
    }

    // The app (or home) below decides the status bar, except under the shade and recents.
    override var childForStatusBarStyle: UIViewController? { SystemUI.shared.statusBarSource }
    override var childForStatusBarHidden: UIViewController? { SystemUI.shared.statusBarSource }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        SystemUI.shared.recentsVisible ? .lightContent : .default
    }
    override var prefersStatusBarHidden: Bool { false }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
}

/// Everything the overlay window draws.
struct SystemUIRoot: View {
    private let ui = SystemUI.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if ui.recentsVisible {
                    RecentsView(size: geo.size)
                        .transition(.opacity)
                }
                ShadeView(size: geo.size)
                // status bar: pull down for the shade (anywhere along the top edge). Stays in the
                // hierarchy while its drag opens the shade (removing it would cancel the gesture).
                Color.clear
                    .frame(width: geo.size.width, height: ui.topStrip)
                    .contentShape(Rectangle())
                    .gesture(ShadeView.pullGesture(ui: ui))
                    .allowsHitTesting(!ui.isShadeVisible || ui.shadeDragging)
                if ui.navMode == .gestural {
                    BackGestureEdges(size: geo.size)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NavigationBarView()
                        .frame(width: geo.size.width, height: ui.navInset)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }
}
