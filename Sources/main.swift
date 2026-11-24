import ClockKit
import FossifyCommons
import SwiftUI

/// The Fossify launcher: the Fossify Launcher home screen, with the bundled ports as its apps.
struct LauncherApp: App {
    // Gallery's and Paint's orientation settings go through OrientationLock.
    @UIApplicationDelegateAdaptor(OrientationLockDelegate.self) private var orientation

    init() {
        // Alarm/timer notification actions must work before Clock is opened.
        ClockNotifications.install()
    }

    var body: some Scene {
        WindowGroup {
            LauncherView().fossifyTheme()
        }
    }
}

LauncherApp.main()
