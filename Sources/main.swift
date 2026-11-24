import CalculatorKit
import CalendarKit
import ClockKit
import FossifyCommons
import GalleryKit
import MusicPlayerKit
import NotesKit
import SwiftUI
import VoiceRecorderKit

/// The Fossify launcher: the Fossify Launcher home screen, with the bundled ports as its apps.
struct LauncherApp: App {
    // Gallery's and Paint's orientation settings go through OrientationLock.
    @UIApplicationDelegateAdaptor(OrientationLockDelegate.self) private var orientation

    init() {
        // Alarm/timer notification actions must work before Clock is opened.
        ClockNotifications.install()
        LauncherSystemSettings.register()
        // Home-screen widgets (widgets-ios): publish snapshots to the app group and handle the intents
        // iOS runs in this process (music/record buttons) even when it was started in the background.
        CalculatorWidgetData.install()
        CalendarWidgetData.install()
        ClockWidgetData.install()
        GalleryWidgetData.install()
        MusicPlayerWidgetData.install()
        NotesWidgetData.install()
        VoiceRecorderWidgetData.install()
    }

    var body: some Scene {
        WindowGroup {
            LauncherView().fossifyTheme()
        }
    }
}

LauncherApp.main()
