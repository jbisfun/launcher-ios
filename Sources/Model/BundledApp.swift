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
import ThankYouKit
import UIKit
import UniformTypeIdentifiers
import VoiceRecorderKit

/// One app bundled into the launcher: what the Android launcher calls an installed app.
/// Its raw value is the item's "package name" in the home layout.
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

    /// The app's own 180 px icon, shipped as a loose PNG in AppIcons/ (cached, like upstream's IconCache).
    var icon: UIImage? { IconCache.icon(for: self) }

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

/// IconCache: app icons are read from disk once.
enum IconCache {
    nonisolated(unsafe) private static var icons: [BundledApp: UIImage] = [:]

    static func icon(for app: BundledApp) -> UIImage? {
        if let cached = icons[app] { return cached }
        let name = app.info.name
        let image = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "AppIcons")
            .flatMap(UIImage.init(contentsOfFile:))
            ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:))
        icons[app] = image
        return image
    }
}

/// An app opened from the home screen, with what to hand it.
struct OpenApp: Identifiable {
    let app: BundledApp
    var url: URL?
    var id: BundledApp { app }
}
