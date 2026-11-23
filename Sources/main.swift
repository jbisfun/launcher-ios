import CalculatorKit
import ContactsKit
import FossifyCommons
import SwiftUI
import UIKit

/// One app bundled into the launcher.
enum BundledApp: String, CaseIterable, Identifiable {
    case calculator, contacts

    var id: Self { self }

    var info: AppInfo {
        switch self {
        case .calculator: return .calculator
        case .contacts: return .contacts
        }
    }

    /// The app's own 180 px icon, shipped as a loose PNG in AppIcons/.
    var icon: UIImage? {
        let name = info.name
        return Bundle.main.path(forResource: name, ofType: "png", inDirectory: "AppIcons")
            .flatMap(UIImage.init(contentsOfFile:))
            ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:))
    }
}

/// An app opened from the home screen, with what to hand it.
struct OpenApp: Identifiable {
    let app: BundledApp
    var url: URL?
    var id: BundledApp { app }
}

struct LauncherApp: App {
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
            Group {
                switch item.app {
                case .calculator: CalculatorRoot()
                case .contacts: ContactsRoot(importURL: item.url)
                }
            }
            .environment(\.closeApp) { open = nil }
        }
        // vCards shared to the launcher go to Contacts' import dialog.
        .onOpenURL { url in open = OpenApp(app: .contacts, url: url) }
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

LauncherApp.main()
