import AVFoundation
import ClockKit
import FossifyCommons
import MusicPlayerKit
import Observation
import SwiftUI
import UIKit
import VoiceRecorderKit

/// The quick settings tiles that work from inside an iOS app (AOSP's Wi-Fi, Bluetooth, airplane
/// mode, DND, location, cast, ... can't be toggled by apps on iOS and are left out). Raw values
/// follow AOSP's tile specs where one exists.
enum QSTileSpec: String, CaseIterable, Identifiable {
    case flashlight, dark, rotation, keepon = "caffeine", recorder = "screenrecord", alarm, timer, camera, calculator

    var id: String { rawValue }

    static let defaults: [QSTileSpec] = [.flashlight, .dark, .rotation, .keepon, .alarm, .timer, .camera, .recorder, .calculator]
    /// quick_settings_min_num_tiles
    static let minTiles = 6

    var label: String {
        switch self {
        case .flashlight: return "Flashlight"
        case .dark: return "Dark theme"
        case .rotation: return "Auto-rotate"
        case .keepon: return "Keep screen on"
        case .recorder: return "Record audio"
        case .alarm: return "Alarm"
        case .timer: return "Timer"
        case .camera: return "Camera"
        case .calculator: return "Calculator"
        }
    }

    var icon: String {
        switch self {
        case .flashlight: return "flashlight.on.fill"
        case .dark: return "circle.lefthalf.filled"
        case .rotation: return "rotate.right"
        case .keepon: return "cup.and.saucer.fill"
        case .recorder: return "mic.fill"
        case .alarm: return "alarm.fill"
        case .timer: return "timer"
        case .camera: return "camera.fill"
        case .calculator: return "plusminus"
        }
    }

    /// The bundled app behind an app shortcut tile (long press opens it, like AOSP's long press = settings).
    var app: BundledApp? {
        switch self {
        case .recorder: return .voiceRecorder
        case .alarm, .timer: return .clock
        case .camera: return .camera
        case .calculator: return .calculator
        case .dark: return nil
        default: return nil
        }
    }
}

/// Tile.State: STATE_UNAVAILABLE / INACTIVE / ACTIVE plus the secondary label.
struct QSTileState {
    enum Value { case unavailable, inactive, active }
    var value: Value
    var secondary: String?
}

/// QSTileHost + the tiles' controllers (FlashlightController, RotationLockController, ...).
@MainActor
@Observable
final class QSTileHost {
    private(set) var torchOn = false
    private(set) var autoRotate = SystemDisplay.autoRotate
    private(set) var keepScreenOn = SystemDisplay.keepScreenOn
    var brightness: CGFloat = UIScreen.main.brightness
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIScreen.brightnessDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemUI.shared.tiles.brightness = UIScreen.main.brightness }
        }
    }

    private var torch: AVCaptureDevice? {
        let device = AVCaptureDevice.default(for: .video)
        return device?.hasTorch == true ? device : nil
    }

    /// Re-reads the states other code may have changed (Camera's torch, Settings' display options).
    func refresh() {
        torchOn = torch?.torchMode == .on
        autoRotate = SystemDisplay.autoRotate
        keepScreenOn = SystemDisplay.keepScreenOn
        brightness = UIScreen.main.brightness
    }

    func setBrightness(_ value: CGFloat) {
        brightness = value
        UIScreen.main.brightness = value
    }

    func state(_ spec: QSTileSpec, palette: Palette) -> QSTileState {
        switch spec {
        case .flashlight:
            guard torch != nil else { return QSTileState(value: .unavailable, secondary: "Unavailable") }
            return QSTileState(value: torchOn ? .active : .inactive, secondary: torchOn ? "On" : "Off")
        case .dark:
            return QSTileState(value: palette.dark ? .active : .inactive, secondary: palette.dark ? "On" : "Off")
        case .rotation:
            return QSTileState(value: autoRotate ? .active : .inactive, secondary: autoRotate ? "On" : "Off")
        case .keepon:
            return QSTileState(value: keepScreenOn ? .active : .inactive, secondary: keepScreenOn ? "On" : "Off")
        case .recorder:
            if VoiceRecorderControls.isRecording {
                let d = VoiceRecorderControls.duration
                let time = String(format: "%d:%02d", d / 60, d % 60)
                return QSTileState(value: .active, secondary: VoiceRecorderControls.isPaused ? "Paused \(time)" : time)
            }
            return QSTileState(value: .inactive, secondary: "Tap to start")
        case .alarm: return QSTileState(value: .inactive, secondary: "Clock")
        case .timer: return QSTileState(value: .inactive, secondary: "Clock")
        case .camera, .calculator: return QSTileState(value: .inactive, secondary: nil)
        }
    }

    /// QSTile.click().
    func click(_ spec: QSTileSpec, palette: Palette) {
        let ui = SystemUI.shared
        switch spec {
        case .flashlight:
            guard let device = torch, (try? device.lockForConfiguration()) != nil else { return }
            let on = device.torchMode != .on
            if on { try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
            device.unlockForConfiguration()
            torchOn = on
        case .dark:
            BaseConfig.shared.theme = palette.dark ? .light : .dark
        case .rotation:
            SystemDisplay.setAutoRotate(!autoRotate)
            autoRotate = SystemDisplay.autoRotate
        case .keepon:
            SystemDisplay.setKeepScreenOn(!keepScreenOn)
            keepScreenOn = SystemDisplay.keepScreenOn
        case .recorder:
            VoiceRecorderControls.toggle()
        case .alarm:
            ClockShortcuts.request(.alarm)
            ui.launch(.clock)
        case .timer:
            ClockShortcuts.request(.timer)
            ui.launch(.clock)
        case .camera: ui.launch(.camera)
        case .calculator: ui.launch(.calculator)
        }
    }

    /// QSTile.longClick(): the app behind the tile.
    func longClick(_ spec: QSTileSpec) {
        if let app = spec.app {
            if spec == .timer { ClockShortcuts.request(.timer) }
            if spec == .alarm { ClockShortcuts.request(.alarm) }
            SystemUI.shared.launch(app)
        } else if spec == .dark {
            SystemUI.shared.openLauncherSettings()
        }
    }
}

// MARK: views

/// Colors of the shade, following the Fossify theme (the AOSP shade follows the system theme).
struct ShadeColors {
    let palette: Palette
    var panel: Color { palette.dark ? Color(white: 0.09) : Color(white: 0.95) }
    var surface: Color { palette.dark ? Color(white: 0.19) : Color(white: 0.87) }
    var text: Color { palette.dark ? .white : Color(white: 0.11) }
    var secondary: Color { text.opacity(0.7) }
    var activeTile: Color { palette.primaryColor }
    var onActive: Color { palette.onPrimary }
    var card: Color { palette.dark ? Color(white: 0.15) : .white }
}

/// QSTileViewImpl: 80dp high, qs_corner_radius 28dp, icon + label + secondary label.
struct QSTileView: View {
    @Environment(\.palette) private var palette
    let spec: QSTileSpec
    private let host = SystemUI.shared.tiles

    var body: some View {
        let colors = ShadeColors(palette: palette)
        let state = host.state(spec, palette: palette)
        let active = state.value == .active
        HStack(spacing: 12) {
            Image(systemName: spec.icon)
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.label).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let s = state.secondary {
                    Text(s).font(.system(size: 13)).lineLimit(1).opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? colors.onActive : colors.text)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 72)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(active ? colors.activeTile : colors.surface))
        .opacity(state.value == .unavailable ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            guard state.value != .unavailable else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            host.click(spec, palette: palette)
        }
        .onLongPressGesture { host.longClick(spec) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// BrightnessSliderView: a thick rounded slider with the sun icon on the filled part.
struct BrightnessSlider: View {
    @Environment(\.palette) private var palette
    private let host = SystemUI.shared.tiles

    var body: some View {
        let colors = ShadeColors(palette: palette)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let fill = max(h, CGFloat(host.brightness) * w)
            ZStack(alignment: .leading) {
                Capsule().fill(colors.surface)
                Capsule().fill(colors.activeTile).frame(width: fill)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.onActive)
                    .frame(width: h, height: h)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                host.setBrightness(min(1, max(0, v.location.x / max(w, 1))))
            })
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel("Display brightness")
        .accessibilityValue("\(Int(host.brightness * 100))%")
        .accessibilityAdjustableAction { dir in
            host.setBrightness(min(1, max(0, host.brightness + (dir == .increment ? 0.1 : -0.1))))
        }
    }
}

/// MediaControlPanel: Music Player's current track with previous / play-pause / next.
struct MediaControlCard: View {
    @Environment(\.palette) private var palette
    @State private var artwork: UIImage?

    var body: some View {
        let colors = ShadeColors(palette: palette)
        HStack(spacing: 14) {
            Group {
                if let artwork { Image(uiImage: artwork).resizable().scaledToFill() } else {
                    AppIconImage(app: .musicPlayer, size: 56)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(MusicPlayerSession.title ?? "").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(MusicPlayerSession.artist ?? "").font(.system(size: 13)).foregroundStyle(colors.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { MusicPlayerSession.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 36, height: 44) }
            Button { MusicPlayerSession.playPause() } label: {
                Image(systemName: MusicPlayerSession.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.onActive)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(colors.activeTile))
            }
            Button { MusicPlayerSession.next() } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 44) }
        }
        .foregroundStyle(colors.text)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(colors.card))
        .contentShape(Rectangle())
        .onTapGesture { SystemUI.shared.closeShade(); SystemUI.shared.launch(.musicPlayer) }
        .task(id: MusicPlayerSession.trackChanges) { artwork = await MusicPlayerSession.artwork(size: 112) }
    }
}

/// QSCustomizer: drag tiles to reorder them, tap one to remove it or to add an available one.
struct QSEditView: View {
    @Environment(\.palette) private var palette
    /// In the shade: close button instead of the pushed screen's back button.
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var dragging: QSTileSpec?
    private let config = LauncherConfig.shared

    var body: some View {
        let colors = ShadeColors(palette: palette)
        let current = config.qsTiles
        let available = QSTileSpec.allCases.filter { !current.contains($0) }
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { if let onClose { onClose() } else { dismiss() } } label: {
                    Image(systemName: "arrow.left").font(.system(size: 20)).frame(width: 48, height: 48)
                }
                Text("Edit").font(.system(size: 21, weight: .medium))
                Spacer()
                Menu {
                    Button("Reset") { config.qsTiles = QSTileSpec.defaults }
                } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 48)
                }
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hold and drag to rearrange tiles. Tap a tile to remove it.")
                        .font(.system(size: 14)).foregroundStyle(colors.secondary)
                    grid(current, active: true, colors: colors)
                    Divider().overlay(colors.secondary.opacity(0.4))
                    Text(available.isEmpty ? "All tiles added" : "Tap to add tiles")
                        .font(.system(size: 14)).foregroundStyle(colors.secondary)
                    grid(available, active: false, colors: colors)
                }
                .padding(16)
            }
        }
        .foregroundStyle(colors.text)
        .background(colors.panel.ignoresSafeArea())
    }

    private func grid(_ specs: [QSTileSpec], active: Bool, colors: ShadeColors) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 16) {
            ForEach(specs) { spec in
                VStack(spacing: 8) {
                    Image(systemName: spec.icon)
                        .font(.system(size: 20))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(active ? colors.surface : colors.surface.opacity(0.5)))
                    Text(spec.label).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .opacity(dragging == spec ? 0.4 : 1)
                .contentShape(Rectangle())
                .onTapGesture { toggle(spec, active: active) }
                .draggable(spec.rawValue) {
                    Image(systemName: spec.icon).font(.system(size: 20)).frame(width: 56, height: 56)
                        .background(Circle().fill(colors.surface))
                        .onAppear { dragging = spec }
                }
                .dropDestination(for: String.self) { items, _ in
                    defer { dragging = nil }
                    guard let raw = items.first, let moved = QSTileSpec(rawValue: raw) else { return false }
                    move(moved, onto: spec, active: active)
                    return true
                }
            }
        }
    }

    private func toggle(_ spec: QSTileSpec, active: Bool) {
        var tiles = config.qsTiles
        if active {
            guard tiles.count > QSTileSpec.minTiles else { return }
            tiles.removeAll { $0 == spec }
        } else {
            tiles.append(spec)
        }
        withAnimation(.easeOut(duration: 0.2)) { config.qsTiles = tiles }
    }

    /// Dropped on a current tile: placed there; dropped on an available one: removed.
    private func move(_ moved: QSTileSpec, onto target: QSTileSpec, active: Bool) {
        var tiles = config.qsTiles
        if active {
            guard moved != target else { return }
            tiles.removeAll { $0 == moved }
            let i = tiles.firstIndex(of: target) ?? tiles.count
            tiles.insert(moved, at: i)
        } else {
            guard tiles.contains(moved), tiles.count > QSTileSpec.minTiles else { return }
            tiles.removeAll { $0 == moved }
        }
        withAnimation(.easeOut(duration: 0.2)) { config.qsTiles = tiles }
    }
}
