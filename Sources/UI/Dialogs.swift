import FossifyCommons
import PhotosUI
import SwiftUI
import _PhotosUI_SwiftUI

/// RenameItemDialog: rename a home screen icon or folder.
struct RenameHomeItemDialog: View {
    @Environment(\.dismiss) private var dismiss
    let item: HomeGridItem
    @State private var title: String
    @State private var error: String?

    init(item: HomeGridItem) {
        self.item = item
        _title = State(initialValue: item.title)
    }

    var body: some View {
        DialogFrame(title: "Rename", scroll: false) {
            DialogTextField(placeholder: "", text: $title)
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(.red).padding(.top, 6) }
            DialogButtons(ok: "OK") {
                guard !title.isEmpty else {
                    error = "Value cannot be empty"
                    return
                }
                if let id = item.id, HomeStore.shared.updateItemTitle(title, id: id) {
                    dismiss()
                } else {
                    error = "An unknown error occurred"
                }
            }
        }
    }
}

/// Stand-in for ACTION_SET_WALLPAPER: the bundled AOSP wallpapers, an image from Photos, or none.
struct WallpaperPickerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var thumbnails: [String: UIImage] = [:]
    private let config = LauncherConfig.shared

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Wallpapers")
            ScrollView {
                VStack(spacing: 0) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        row("Pick from Photos", icon: "photo.on.rectangle", selected: config.wallpaper == "custom")
                    }
                    .buttonStyle(.plain)
                    Button {
                        config.wallpaper = ""
                        dismiss()
                    } label: {
                        row("None (theme background)", icon: "circle.slash", selected: config.wallpaper.isEmpty)
                    }
                    .buttonStyle(.plain)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(Wallpapers.names, id: \.self) { name in
                            Button {
                                config.wallpaper = "bundle:\(name)"
                                dismiss()
                            } label: {
                                thumbnail(name)
                            }
                            .buttonStyle(PressedStyle())
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .task { await loadThumbnails() }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self), Wallpapers.saveCustom(data) {
                    config.wallpaper = "custom"
                    config.wallpaperRevision += 1
                    dismiss()
                }
            }
        }
    }

    private func row(_ title: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 28)
            Text(title).font(.system(size: 16))
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(palette.primaryColor) }
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func thumbnail(_ name: String) -> some View {
        let selected = config.wallpaper == "bundle:\(name)"
        return VStack(spacing: 6) {
            Group {
                if let image = thumbnails[name] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    palette.surface
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.primaryColor, lineWidth: selected ? 3 : 0))
            Text(name).font(.system(size: 13)).foregroundStyle(palette.textColor).lineLimit(1)
        }
    }

    private func loadThumbnails() async {
        for name in Wallpapers.names where thumbnails[name] == nil {
            guard let url = Wallpapers.url(name) else { continue }
            let image = await Task.detached { Wallpapers.image(url, maxPixel: 400) }.value
            thumbnails[name] = image
        }
    }
}
