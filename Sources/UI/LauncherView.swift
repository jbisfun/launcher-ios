import BrowserKit
import CalculatorKit
import CalendarKit
import CameraKit
import ClockKit
import ContactsKit
import DocumentsKit
import FileManagerKit
import FossifyCommons
import GalleryKit
import KeyboardKit
import MessagesKit
import MusicPlayerKit
import NotesKit
import PaintKit
import PhoneKit
import SettingsKit
import SwiftUI
import ThankYouKit
import VoiceRecorderKit

/// The opened app's root view (launchApp), hosted in the app's own window by SystemUI.
struct AppView: View {
    let item: OpenApp

    var body: some View {
        switch item.app {
        case .browser: BrowserRoot(openURL: item.url)
        case .calculator: CalculatorRoot()
        case .calendar: CalendarRoot(importURL: item.url)
        case .camera: CameraRoot()
        case .clock: ClockRoot()
        case .contacts: ContactsRoot(importURL: item.url)
        case .documents: DocumentsRoot(openURL: item.url)
        case .fileManager: FileManagerRoot(openURL: item.url)
        case .gallery: GalleryRoot()
        case .keyboard: KeyboardRoot(openURL: item.url)
        case .messages: MessagesRoot(importURL: item.url)
        case .musicPlayer: MusicPlayerRoot(openURL: item.url)
        case .notes: NotesRoot(openURL: item.url)
        case .paint: PaintRoot(openURL: item.url)
        case .phone: PhoneRoot()
        case .settings: SettingsRoot()
        case .thankYou:
            // Lists the bundled apps; tapping one switches to it.
            ThankYouRoot(apps: BundledApp.allCases.map { .hosted($0.info, icon: $0.icon) },
                         launchApp: { id in
                             if let app = BundledApp.allCases.first(where: { $0.info.port == id }) { SystemUI.shared.launch(app) }
                         })
        case .voiceRecorder: VoiceRecorderRoot()
        }
    }
}

/// MainActivity: the home screen, plus the screens and dialogs it opens. Opened apps get their own
/// windows above it (SystemUI), with the navigation bar and the shade in an overlay window.
struct LauncherView: View {
    @Environment(\.palette) private var palette
    @State private var controller = HomeController()
    @State private var wallpaper: UIImage?
    private let config = LauncherConfig.shared
    private let ui = SystemUI.shared

    var body: some View {
        @Bindable var controller = controller
        HomeScreenView(controller: controller, wallpaper: wallpaper)
            .toast($controller.toast)
            .onAppear {
                controller.launch = { app, url in SystemUI.shared.launch(app, url: url) }
                controller.expandNotifications = { SystemUI.shared.openShade() }
                ui.home = controller
                controller.onAppear()
                // Keep screen on / auto-rotate apply to every app (quick settings tiles, Settings).
                SystemDisplay.install()
                // the window exists once the first frame is on screen
                DispatchQueue.main.async { SystemUI.shared.install() }
            }
            .onChange(of: config.navigationMode) { ui.refreshInsets() }
            .task(id: "\(config.wallpaper)#\(config.wallpaperRevision)") { await loadWallpaper() }
            .sheet(item: $controller.renaming) { item in RenameHomeItemDialog(item: item).fossifyTheme() }
            .sheet(item: $controller.aboutApp) { app in AboutView(app: app.info).fossifyTheme() }
            .sheet(item: $controller.configuring, onDismiss: nil) { request in
                request.kind.configure?(controller.widgetContext(request.item)) { ok in controller.configureDone(ok) }
                    .fossifyTheme()
                    .onDisappear { controller.configureDismissed(request) }
            }
            .fullScreenCover(isPresented: $controller.showSettings) { LauncherSettingsRoot() }
            .sheet(isPresented: $controller.showWallpapers) { WallpaperPickerView().fossifyTheme() }
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .vertical)
            .onOpenURL { url in
                if url.scheme == KeyboardRoot.urlScheme {
                    // the keyboard extension's settings / clipboard buttons
                    ui.launch(.keyboard, url: url)
                } else if let link = WidgetBridge.parse(url) {
                    // a home-screen widget tap (fossify://open/<app>?...)
                    if let app = BundledApp.widgetApp(link.app, url: url) { ui.launch(app) }
                } else {
                    // files shared to the launcher go to the app that handles them
                    ui.launch(.handling(url), url: url)
                }
            }
    }

    private func loadWallpaper() async {
        guard let url = Wallpapers.url(forChoice: config.wallpaper) else {
            wallpaper = nil
            return
        }
        let screen = UIScreen.main.bounds.size
        let maxPixel = max(screen.width, screen.height) * UIScreen.main.scale
        wallpaper = await Task.detached { Wallpapers.image(url, maxPixel: maxPixel) }.value
        if let wallpaper { ui.wallpaperBottomIsLight = Wallpapers.bottomLuminance(wallpaper) > 0.6 }
    }
}

/// For `.sheet(item:)` (rename); placed items always have an id.
extension HomeGridItem: Identifiable {}
