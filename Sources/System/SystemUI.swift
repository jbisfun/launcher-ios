import ClockKit
import FossifyCommons
import Observation
import SwiftUI
import UIKit

/// An opened app (an Android task). Its window, and so its whole SwiftUI state, stays alive while
/// the task is in recents; hidden windows also hide the app's own sheets and alerts.
@MainActor
@Observable
final class AppTask: Identifiable {
    let id = UUID()
    let app: BundledApp
    @ObservationIgnored var window: AppWindow?
    /// TaskSnapshot: taken whenever the app leaves the screen.
    var snapshot: UIImage?
    @ObservationIgnored let dispatcher = BackPressedDispatcher()

    init(app: BundledApp) { self.app = app }
}

/// The app's window: ordinary level above the home screen's window, below the system UI overlay.
final class AppWindow: UIWindow {}

/// The app's root view controller: with 3-button navigation the iOS home indicator stays visible
/// below the navigation bar; gesture navigation's handle replaces it. The first swipe from the
/// top/bottom edge goes to the system UI overlay.
final class AppHostingController: UIHostingController<AnyView> {
    override var prefersHomeIndicatorAutoHidden: Bool {
        MainActor.assumeIsolated { SystemUI.shared.navMode == .gestural }
    }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
}

/// SystemUI + ActivityTaskManager of the launcher: the opened apps and their windows, the
/// navigation bar (Back/Home/Recents or gestures), the recents overview and the notification
/// shade. Everything lives in one process, so "apps" are windows of this scene.
@MainActor
@Observable
final class SystemUI {
    static let shared = SystemUI()

    /// ActivityTaskManager's recents cap for low-RAM devices (config_maxRecentTasks... the
    /// launcher keeps every task's window alive, so the list is short).
    static let maxTasks = 8
    /// navigation_bar_height / navigation_key_width.
    static let navBarHeight: CGFloat = 48
    static let navKeyWidth: CGFloat = 70
    /// Gesture navigation: the back gesture's edge width (config_backGestureInset).
    static let backGestureInset: CGFloat = 20

    /// Most recent first.
    private(set) var tasks: [AppTask] = []
    private(set) var foreground: AppTask?
    private(set) var recentsVisible = false
    /// The task shown before the overview opened (Back from the overview returns to it).
    @ObservationIgnored private var recentsReturnTask: AppTask?

    // shade
    /// 0 = closed, 1 = the quick quick settings panel fully pulled down.
    var shadeOpen: CGFloat = 0
    var qsExpanded = false
    var editingTiles = false
    var shadeDragging = false
    var isShadeVisible: Bool { shadeOpen > 0 || shadeDragging || editingTiles }

    // gestures
    /// Gesture navigation feedback: 0...1 while swiping up from the handle.
    var homeGestureProgress: CGFloat = 0
    var backGesture: BackGestureState?

    // geometry (overlay window)
    private(set) var bounds: CGRect = UIScreen.main.bounds
    private(set) var rawInsets: UIEdgeInsets = .zero
    private(set) var keyboardVisible = false
    /// Mean luminance of the wallpaper's bottom strip: the nav bar icons over home turn dark on light wallpapers.
    var wallpaperBottomIsLight = false

    @ObservationIgnored weak var home: HomeController?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private weak var mainWindow: UIWindow?
    @ObservationIgnored private var overlay: OverlayWindow?
    @ObservationIgnored private var insetTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    let config = LauncherConfig.shared
    let notifications = ShadeNotifications()
    let tiles = QSTileHost()

    private init() {}

    var navMode: NavigationMode { config.navigationMode }

    /// What the navigation bar / gesture area covers at the bottom of the screen; apps are inset by it.
    /// The 3-button bar sits above the iOS home indicator (it doesn't cover it).
    var navInset: CGFloat {
        navMode == .threeButton ? Self.navBarHeight + rawInsets.bottom : max(rawInsets.bottom, 20)
    }

    /// The status bar strip that pulls the shade down.
    var topStrip: CGFloat { max(rawInsets.top, 20) }

    // MARK: setup

    /// Called once the home screen's window exists: adds the system UI overlay window.
    func install() {
        guard overlay == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let main = scene.windows.first(where: { $0.isKeyWindow && !($0 is AppWindow) })
                ?? scene.windows.first(where: { $0.rootViewController != nil && !($0 is OverlayWindow) && !($0 is AppWindow) })
        else { return }
        self.scene = scene
        mainWindow = main
        let window = OverlayWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 2)
        let controller = OverlayController(rootView: AnyView(SystemUIRoot().fossifyTheme()))
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.backgroundColor = .clear
        window.isHidden = false
        overlay = window
        layoutChanged(window)

        // Sheets come and go without callbacks: keep their bottom inset in sync.
        insetTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated { SystemUI.shared.refreshInsets() }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemUI.shared.keyboardVisible = true }
        })
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemUI.shared.keyboardVisible = false }
        })
    }

    func layoutChanged(_ window: UIWindow) {
        if bounds != window.bounds { bounds = window.bounds }
        if rawInsets != window.safeAreaInsets { rawInsets = window.safeAreaInsets }
        refreshInsets()
    }

    /// Insets the home screen, every app and their full-height sheets by the navigation bar.
    func refreshInsets() {
        let extra = max(0, navInset - rawInsets.bottom)
        if let mainWindow { inset(mainWindow, extra) }
        for task in tasks { if let w = task.window { inset(w, extra) } }
    }

    private func inset(_ window: UIWindow, _ extra: CGFloat) {
        guard let root = window.rootViewController else { return }
        if root.additionalSafeAreaInsets.bottom != extra { root.additionalSafeAreaInsets.bottom = extra }
        var presented = root.presentedViewController
        while let vc = presented {
            if !(vc is UIAlertController), let v = vc.viewIfLoaded, v.window === window,
               abs(v.convert(v.bounds, to: window).maxY - window.bounds.maxY) < 1,
               vc.additionalSafeAreaInsets.bottom != extra {
                vc.additionalSafeAreaInsets.bottom = extra
            }
            presented = vc.presentedViewController
        }
    }

    /// Hit testing of the overlay window: everything else falls through to the windows below.
    func overlayHandles(_ p: CGPoint) -> Bool {
        if recentsVisible || isShadeVisible || backGesture != nil { return true }
        if p.y < topStrip { return true }
        if p.y > bounds.height - navInset { return true }
        if navMode == .gestural && (p.x < Self.backGestureInset || p.x > bounds.width - Self.backGestureInset) { return true }
        return false
    }

    /// The view controller whose status bar style applies (the overlay forwards to it).
    var statusBarSource: UIViewController? {
        if isShadeVisible || recentsVisible { return nil }
        return topPresented(of: (foreground?.window ?? mainWindow)?.rootViewController)
    }

    private func topPresented(of vc: UIViewController?) -> UIViewController? {
        var top = vc
        while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
        return top
    }

    private func updateStatusBar() {
        overlay?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: tasks

    /// startActivity: opens an app (brought to front when it's in recents, recreated if it gets a file).
    func launch(_ app: BundledApp, url: URL? = nil) {
        let task: AppTask
        if let existing = tasks.first(where: { $0.app == app }) {
            task = existing
            if url != nil || task.window == nil {
                task.window?.isHidden = true
                task.window = makeWindow(for: task, url: url)
            }
            tasks.removeAll { $0 === task }
            tasks.insert(task, at: 0)
        } else {
            task = AppTask(app: app)
            task.window = makeWindow(for: task, url: url)
            tasks.insert(task, at: 0)
            while tasks.count > Self.maxTasks, let last = tasks.last { remove(last) }
        }
        show(task)
    }

    private func makeWindow(for task: AppTask, url: URL?) -> AppWindow? {
        guard let scene else { return nil }
        let root = AppView(item: OpenApp(app: task.app, url: url))
            .fossifyTheme()
            .environment(\.backPressedDispatcher, task.dispatcher)
            .environment(\.finishApp) { [weak task] in
                MainActor.assumeIsolated { if let task { SystemUI.shared.finish(task) } }
            }
        let controller = AppHostingController(rootView: AnyView(root))
        let window = AppWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.rootViewController = controller
        window.isHidden = true
        inset(window, max(0, navInset - rawInsets.bottom))
        return window
    }

    private func show(_ task: AppTask) {
        if let current = foreground, current !== task { moveToBack(current, animated: false) }
        recentsVisible = false
        recentsReturnTask = nil
        closeShade()
        let alreadyShown = foreground === task && task.window?.isHidden == false
        foreground = task
        if !alreadyShown, let window = task.window {
            // Only the content view is scaled: a transformed UIWindow gets its safe area insets
            // from the shrunken frame (notch / home indicator insets go wrong).
            let content = window.rootViewController?.view
            window.alpha = 0
            content?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            window.isHidden = false
            window.makeKey()
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                window.alpha = 1
                content?.transform = .identity
            }
        }
        updateStatusBar()
    }

    /// The task leaves the screen: snapshot, hide (Camera releases its window, like a killed process).
    private func moveToBack(_ task: AppTask, animated: Bool) {
        captureSnapshot(task)
        guard let window = task.window else { return }
        let content = window.rootViewController?.view
        let finish = {
            window.isHidden = true
            window.alpha = 1
            content?.transform = .identity
            if !task.app.staysAliveInRecents { task.window = nil }
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
                window.alpha = 0
                content?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            } completion: { _ in
                // The app may have come back in the meantime.
                if SystemUI.shared.foreground !== task { finish() } else { window.alpha = 1; content?.transform = .identity }
            }
        } else {
            finish()
        }
    }

    func captureSnapshot(_ task: AppTask) {
        guard let window = task.window, !window.isHidden, window.bounds.width > 0 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, window.screen.scale / 2)
        task.snapshot = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    /// Activity.finish() / swiping the task away: the app's window and state are released.
    func finish(_ task: AppTask) {
        if foreground === task {
            foreground = nil
            moveToBack(task, animated: true)
            mainWindow?.makeKey()
            updateStatusBar()
        }
        remove(task)
    }

    private func remove(_ task: AppTask) {
        tasks.removeAll { $0 === task }
        if recentsReturnTask === task { recentsReturnTask = nil }
        if foreground !== task {
            task.window?.isHidden = true
            task.window = nil
        }
        task.snapshot = nil
    }

    func clearAllTasks() {
        for task in tasks { remove(task) }
        goHome()
    }

    // MARK: navigation buttons

    /// KEYCODE_HOME: back to the home screen, closing its drawers, folders and launcher screens.
    func goHome() {
        recentsVisible = false
        recentsReturnTask = nil
        closeShade()
        if let task = foreground {
            foreground = nil
            moveToBack(task, animated: true)
        }
        mainWindow?.makeKey()
        home?.homePressed()
        updateStatusBar()
    }

    /// KEYCODE_BACK.
    func back() {
        if editingTiles { editingTiles = false; return }
        if isShadeVisible {
            if qsExpanded { withAnimation(.easeOut(duration: 0.2)) { qsExpanded = false } } else { closeShade() }
            return
        }
        if recentsVisible {
            if let task = recentsReturnTask, tasks.contains(where: { $0 === task }) { show(task) } else { goHome() }
            return
        }
        if let task = foreground, let window = task.window {
            if keyboardVisible { window.endEditing(true); return }
            if BackHandling.handle(in: window) { return }
            if task.dispatcher.onBackPressed() { return }
            // Android 12+: Back on a task's root activity moves it to the background.
            goHome()
        } else {
            if keyboardVisible { mainWindow?.endEditing(true); return }
            if let mainWindow, BackHandling.handle(in: mainWindow) { return }
            home?.backPressed()
        }
    }

    /// KEYCODE_APP_SWITCH: the overview; pressed again, it switches to the previous app.
    func toggleRecents() {
        if recentsVisible {
            let others = tasks.filter { $0 !== recentsReturnTask }
            if let previous = recentsReturnTask == nil ? tasks.first : others.first { show(previous) } else { goHome() }
            return
        }
        closeShade()
        if let task = foreground {
            moveToBack(task, animated: false)
            recentsReturnTask = task
            foreground = nil
        }
        mainWindow?.makeKey()
        withAnimation(.easeOut(duration: 0.2)) { recentsVisible = true }
        updateStatusBar()
    }

    func switchTo(_ task: AppTask) {
        if task.window == nil { task.window = makeWindow(for: task, url: nil) }
        tasks.removeAll { $0 === task }
        tasks.insert(task, at: 0)
        show(task)
    }

    // MARK: shade

    func openShade(expanded: Bool = false) {
        notifications.refresh()
        tiles.refresh()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            shadeOpen = 1
            qsExpanded = expanded
        }
        updateStatusBar()
    }

    func closeShade() {
        guard isShadeVisible || qsExpanded else { return }
        editingTiles = false
        withAnimation(.easeOut(duration: 0.2)) {
            shadeOpen = 0
            qsExpanded = false
        }
        updateStatusBar()
    }

    func shadeSettled() { updateStatusBar() }

    /// A notification tapped in the shade: its app opens (on the right tab for Clock).
    func open(_ notification: ShadeNotification) {
        notifications.dismiss(notification)
        closeShade()
        guard let app = notification.app else { return }
        if app == .clock {
            let id = notification.identifier
            ClockShortcuts.request(id.hasPrefix("timer-") ? .timer : .alarm)
        }
        launch(app)
    }

    /// The shade's settings button opens the Settings app, like AOSP.
    func openLauncherSettings() {
        launch(.settings)
    }

    // MARK: navigation bar look

    /// Light (white) icons, and the bar's background (nil = transparent over the content).
    func navBarStyle(_ palette: Palette) -> (light: Bool, background: Color?) {
        if recentsVisible || shadeOpen > 0.5 || editingTiles { return (true, nil) }
        if foreground != nil { return (palette.dark, palette.backgroundColor) }
        if let home, home.isAllAppsExpanded || home.isWidgetsExpanded || home.showSettings { return (palette.dark, nil) }
        if config.wallpaper.isEmpty { return (palette.dark, nil) }
        return (!wallpaperBottomIsLight, nil)
    }
}

/// The back gesture in progress (NavigationBarEdgePanel).
struct BackGestureState: Equatable {
    var fromLeft: Bool
    var y: CGFloat
    var distance: CGFloat
}

extension BundledApp {
    /// Camera's capture session must not run behind other apps: its task keeps only a snapshot
    /// and restarts when reopened (as after Android killed its process).
    var staysAliveInRecents: Bool { self != .camera }
}
