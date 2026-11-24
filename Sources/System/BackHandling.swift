import UIKit

/// The window part of Back: the topmost presented sheet / alert is dismissed (a navigation stack
/// inside it is popped first), else the topmost visible navigation stack is popped. SwiftUI's
/// NavigationStack sits on a UINavigationController, so popping it keeps the path binding in sync
/// (like the swipe-back gesture); sheets are dismissed through their presentation controller's
/// delegate, the path an interactive swipe-down takes, so `isPresented`/`item` bindings reset.
@MainActor
enum BackHandling {
    static func handle(in window: UIWindow) -> Bool {
        guard let root = window.rootViewController else { return false }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        if let nav = visibleNavigationController(in: top), nav.viewControllers.count > 1, nav.transitionCoordinator == nil {
            nav.popViewController(animated: true)
            return true
        }
        guard top !== root else { return false }
        if top.isBeingPresented { return true }
        if let alert = top as? UIAlertController { return cancel(alert) }
        dismiss(top)
        return true
    }

    /// A non-cancelable dialog (interactiveDismissDisabled) ignores Back, like Android.
    private static func dismiss(_ vc: UIViewController) {
        if vc.isModalInPresentation { return }
        let controller = vc.presentationController
        if let controller, let delegate = controller.delegate,
           delegate.presentationControllerShouldDismiss?(controller) == false {
            delegate.presentationControllerDidAttemptToDismiss?(controller)
            return
        }
        controller.flatMap { $0.delegate?.presentationControllerWillDismiss?($0) }
        vc.presentingViewController?.dismiss(animated: true) {
            if let controller { controller.delegate?.presentationControllerDidDismiss?(controller) }
        }
    }

    private typealias AlertHandler = @convention(block) (UIAlertAction) -> Void

    /// Alerts are canceled through their cancel action (the one-button ones through that button),
    /// so SwiftUI's alert state resets; alerts with several choices and no cancel stay (not cancelable).
    private static func cancel(_ alert: UIAlertController) -> Bool {
        let action = alert.actions.first { $0.style == .cancel } ?? (alert.actions.count == 1 ? alert.actions.first : nil)
        guard let action else { return true }
        var handler: AlertHandler?
        if action.responds(to: NSSelectorFromString("handler")), let block = action.value(forKey: "handler") {
            handler = unsafeBitCast(block as AnyObject, to: AlertHandler.self)
        }
        alert.presentingViewController?.dismiss(animated: true) { handler?(action) }
        return true
    }

    /// The deepest on-screen navigation controller (tab bars: the selected tab only).
    private static func visibleNavigationController(in vc: UIViewController) -> UINavigationController? {
        guard isOnScreen(vc) else { return nil }
        if let tabs = vc as? UITabBarController, let selected = tabs.selectedViewController {
            return visibleNavigationController(in: selected)
        }
        if let nav = vc as? UINavigationController {
            if let top = nav.topViewController, let inner = deepest(in: top) { return inner }
            return nav
        }
        return deepest(in: vc)
    }

    private static func deepest(in vc: UIViewController) -> UINavigationController? {
        for child in vc.children.reversed() {
            if let nav = visibleNavigationController(in: child) { return nav }
        }
        return nil
    }

    private static func isOnScreen(_ vc: UIViewController) -> Bool {
        guard let view = vc.viewIfLoaded, view.window != nil, !view.isHidden, view.alpha > 0.01 else { return false }
        var v: UIView? = view.superview
        while let s = v {
            if s.isHidden || s.alpha < 0.01 { return false }
            v = s.superview
        }
        return true
    }
}
