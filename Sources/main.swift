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
import UIKit
import UniformTypeIdentifiers
import VoiceRecorderKit

/// One app bundled into the launcher.
enum BundledApp: String, CaseIterable, Identifiable {
    case calculator, calendar, camera, clock, contacts, documents, fileManager, gallery, keyboard, messages, musicPlayer, notes, paint,
         phone, thankYou, voiceRecorder

    var id: Self { self }

    var info: AppInfo {
        switch self {
        case .calculator: return .calculator
        case .calendar: return .calendar
        case .camera: return .camera
        case .clock: return .clock
        case .contacts: return .contacts
        case .documents: return .documents
        case .fileManager: return .fileManager
        case .gallery: return .gallery
        case .keyboard: return .keyboard
        case .messages: return .messages
        case .musicPlayer: return .musicPlayer
        case .notes: return .notes
        case .paint: return .paint
        case .phone: return .phone
        case .thankYou: return .thankYou
        case .voiceRecorder: return .voiceRecorder
        }
    }

    /// The app's own 180 px icon, shipped as a loose PNG in AppIcons/.
    var icon: UIImage? {
        let name = info.name
        return Bundle.main.path(forResource: name, ofType: "png", inDirectory: "AppIcons")
            .flatMap(UIImage.init(contentsOfFile:))
            ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:))
    }

    /// The app that opens a file shared to the launcher.
    static func handling(_ url: URL) -> BundledApp {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        let type = UTType(filenameExtension: ext)
        func conforms(_ t: UTType) -> Bool { type?.conforms(to: t) ?? false }
        if url.hasDirectoryPath { return .fileManager }
        switch ext {
        case "vcf": return .contacts
        case "ics": return .calendar
        case "txt": return .notes
        case "json", "xml":
            if name.contains("messages") || name.contains("sms") || name.contains("mms") { return .messages }
            if name.contains("notes") { return .notes }
            return .documents
        case "pdf", "docx", "md", "markdown", "csv", "tsv", "html", "htm", "xhtml", "yaml", "yml": return .documents
        default: break
        }
        if conforms(.audio) { return .musicPlayer }
        if conforms(.image) { return .paint }
        if conforms(.text) { return .documents }
        return .fileManager
    }
}

/// An app opened from the home screen, with what to hand it.
struct OpenApp: Identifiable {
    let app: BundledApp
    var url: URL?
    var id: BundledApp { app }
}

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

struct LauncherView: View {
    @Environment(\.palette) private var palette
    @State private var open: OpenApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fossify")
                .font(.system(size: 28, weight: .medium))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 16)], spacing: 24) {
                    ForEach(BundledApp.allCases) { app in
                        Button { open = OpenApp(app: app) } label: { tile(app) }
                            .buttonStyle(PressedStyle())
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paletteBackground()
        .fullScreenCover(item: $open) { item in
            AppView(item: item, open: $open).environment(\.closeApp) { open = nil }
        }
        // Files shared to the launcher go to the app that handles them.
        .onOpenURL { url in open = OpenApp(app: .handling(url), url: url) }
    }

    private func tile(_ app: BundledApp) -> some View {
        VStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(uiImage: icon).resizable()
                } else {
                    palette.primaryColor.overlay(
                        Image(systemName: app.info.icon).font(.system(size: 28)).foregroundStyle(palette.onPrimary))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(app.info.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(palette.textColor)
        }
    }
}

/// The opened app's root view.
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
        case .keyboard: KeyboardRoot()
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

LauncherApp.main()
