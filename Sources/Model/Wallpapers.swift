import ImageIO
import UIKit

/// iOS apps can't read or set the system wallpaper, so the home screen draws its own: one of the
/// AOSP wallpapers in Wallpapers.bundle, an image picked from Photos, or the theme background.
enum Wallpapers {
    static var bundleURL: URL? { Bundle.main.url(forResource: "Wallpapers", withExtension: "bundle") }

    /// Display titles of the bundled wallpapers ("Android 14", "Kepler", ...).
    static let names: [String] = {
        guard let dir = bundleURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.filter { $0.lowercased().hasSuffix(".jpg") }
            .map { String($0.dropLast(4)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    static func url(_ name: String) -> URL? { bundleURL?.appendingPathComponent("\(name).jpg") }

    static var customURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Launcher/wallpaper", isDirectory: false)
    }

    static func url(forChoice choice: String) -> URL? {
        if choice.hasPrefix("bundle:") { return url(String(choice.dropFirst(7))) }
        if choice == "custom" { return customURL }
        return nil
    }

    static func saveCustom(_ data: Data) -> Bool {
        try? FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: customURL, options: .atomic)) != nil
    }

    /// Downsampled decode, so a 4K wallpaper doesn't sit in memory at full size.
    static func image(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// WallpaperColors.supportsDarkText() before Android 12: the wallpaper's average color's
    /// contrast color is dark grey.
    static func supportsDarkText(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let y = (Double(pixel[0]) * 299 + Double(pixel[1]) * 587 + Double(pixel[2]) * 114) / 1000
        return y >= 149
    }
}
