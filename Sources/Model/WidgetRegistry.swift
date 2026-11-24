import CalculatorKit
import CalendarKit
import ClockKit
import FossifyCommons
import GalleryKit
import MusicPlayerKit
import NotesKit
import SwiftUI
import VoiceRecorderKit

/// The widgets each bundled app offers (Android: AppWidgetManager.installedProviders), in the
/// order the widgets list shows them (by app title, like WidgetsFragment).
let widgetProviders: [(BundledApp, [HomeWidgetKind])] = [
    (.calculator, CalculatorWidgets.all),
    (.calendar, CalendarWidgets.all),
    (.clock, ClockWidgets.all),
    (.gallery, GalleryWidgets.all),
    (.musicPlayer, MusicPlayerWidgets.all),
    (.notes, NotesWidgets.all),
    (.voiceRecorder, VoiceRecorderWidgets.all),
]

enum WidgetRegistry {
    /// The widget kind with this id and the app offering it.
    static func kind(_ id: String) -> (BundledApp, HomeWidgetKind)? {
        for (app, kinds) in widgetProviders {
            if let kind = kinds.first(where: { $0.id == id }) { return (app, kind) }
        }
        return nil
    }
}
