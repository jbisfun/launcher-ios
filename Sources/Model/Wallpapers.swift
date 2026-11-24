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

    /// RegionSamplingHelper: luminance (0...1) of the wallpaper behind the navigation bar (its
    /// bottom 8%), for light or dark navigation icons over the home screen.
    static func bottomLuminance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let stripHeight = max(1, Int(Double(cg.height) * 0.08))
        guard let strip = cg.cropping(to: CGRect(x: 0, y: cg.height - stripHeight, width: cg.width, height: stripHeight)) else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) * 0.299 + Double(pixel[1]) * 0.587 + Double(pixel[2]) * 0.114) / 255
    }
}
