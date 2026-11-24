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
import SwiftUI
import ThankYouKit
import VoiceRecorderKit

/// The opened app's root view (launchApp).
struct AppView: View {
    let item: OpenApp
    @Binding var open: OpenApp?

    var body: some View {
        switch item.app {
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
        case .thankYou:
            // Lists the bundled apps; tapping one switches to it.
            ThankYouRoot(apps: BundledApp.allCases.map { .hosted($0.info, icon: $0.icon) },
                         launchApp: { id in
                             if let app = BundledApp.allCases.first(where: { $0.info.port == id }) { open = OpenApp(app: app) }
                         })
        case .voiceRecorder: VoiceRecorderRoot()
        }
    }
}

/// MainActivity: the home screen, plus the screens and dialogs it opens.
struct LauncherView: View {
    @Environment(\.palette) private var palette
    @State private var controller = HomeController()
    @State private var open: OpenApp?
    @State private var wallpaper: UIImage?
    private let config = LauncherConfig.shared

    var body: some View {
        @Bindable var controller = controller
        HomeScreenView(controller: controller, wallpaper: wallpaper)
            .toast($controller.toast)
            .onAppear {
                controller.launch = { app, url in open = OpenApp(app: app, url: url) }
                controller.onAppear()
            }
            .task(id: "\(config.wallpaper)#\(config.wallpaperRevision)") { await loadWallpaper() }
            .fullScreenCover(item: $open) { item in
                AppView(item: item, open: $open).environment(\.closeApp) {
                    open = nil
                    controller.homePressed()
                }
            }
            .sheet(item: $controller.renaming) { item in RenameHomeItemDialog(item: item).fossifyTheme() }
            .sheet(item: $controller.aboutApp) { app in AboutView(app: app.info).fossifyTheme() }
            .sheet(item: $controller.configuring, onDismiss: nil) { request in
                request.kind.configure?(controller.widgetContext(request.item)) { ok in controller.configureDone(ok) }
                    .fossifyTheme()
                    .onDisappear { controller.configureDismissed(request) }
            }
            .fullScreenCover(isPresented: $controller.showSettings) { LauncherSettingsRoot() }
            .sheet(isPresented: $controller.showWallpapers) { WallpaperPickerView().fossifyTheme() }
            .onOpenURL { url in
                if url.scheme == KeyboardRoot.urlScheme {
                    // the keyboard extension's settings / clipboard buttons
                    open = OpenApp(app: .keyboard, url: url)
                } else {
                    // files shared to the launcher go to the app that handles them
                    open = OpenApp(app: .handling(url), url: url)
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
    }
}

/// For `.sheet(item:)` (rename); placed items always have an id.
extension HomeGridItem: Identifiable {}
