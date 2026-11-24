import FossifyCommons
import SwiftUI

/// An app's icon as drawn on the grid and in the drawer.
struct AppIconImage: View {
    @Environment(\.palette) private var palette
    let app: BundledApp?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = app?.icon {
                Image(uiImage: icon).resizable()
            } else {
                palette.primaryColor.overlay(
                    Image(systemName: app?.info.icon ?? "app").font(.system(size: size * 0.42)).foregroundStyle(palette.onPrimary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

/// HomeScreenFolder.generateDrawable: a circle with the folder's apps laid out in a grid.
struct FolderIconImage: View {
    @Environment(\.palette) private var palette
    let items: [HomeGridItem]
    let size: CGFloat

    var body: some View {
        let count = max(items.count, 1)
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let scaledCellSize = size / CGFloat(columns)
        let gap = scaledCellSize / 4
        let iconSize = (size - CGFloat(columns + 1) * gap) / CGFloat(columns)
        let extraY = rows < columns ? (iconSize + gap) / 2 : 0
        ZStack(alignment: .topLeading) {
            Circle().fill(palette.backgroundColor.opacity(0.9))
            ForEach(items, id: \.id) { item in
                let row = item.left / columns, column = item.left % columns
                AppIconImage(app: item.app, size: iconSize)
                    .offset(x: gap + CGFloat(column) * (iconSize + gap), y: extraY + gap + CGFloat(row) * (iconSize + gap))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// An item's label: white with a dark shadow over a wallpaper (textPaint), the theme's text color
/// with a contrasting shadow otherwise and inside folders (contrastTextPaint).
struct HomeLabel: View {
    @Environment(\.palette) private var palette
    let title: String
    let width: CGFloat
    let onWallpaper: Bool

    var body: some View {
        Text(title)
            .font(.system(size: HomeGeometry.labelFontSize))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(onWallpaper ? Color.white : palette.textColor)
            .shadow(color: onWallpaper ? .black : palette.text.contrastColor, radius: 1.5)
            .frame(width: max(width, 1), alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
    }
}
