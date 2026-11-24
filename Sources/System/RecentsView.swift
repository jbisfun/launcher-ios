import FossifyCommons
import SwiftUI

/// The overview (RecentsView of Launcher3 quickstep, kept to the plain AOSP carousel): one card per
/// task with its icon and last snapshot, newest on the right. Swipe sideways to browse, swipe a
/// card up to remove the task, tap a card to switch to it, tap outside to go home, "Clear all"
/// past the oldest task.
struct RecentsView: View {
    let size: CGSize
    private let ui = SystemUI.shared

    /// Fractional index of the centered card in display order (oldest = 0); -1 = "Clear all".
    @State private var position: CGFloat = 0
    @State private var startPosition: CGFloat?
    @State private var axis: Axis?
    @State private var dragged: (id: UUID, dy: CGFloat)?
    @State private var removing: Set<UUID> = []
    @State private var didAppear = false

    private var ordered: [AppTask] { ui.tasks.reversed() }
    private var cardWidth: CGFloat { min(size.width * 0.68, (size.height - ui.navInset - 200) * size.width / max(size.height, 1)) }
    private var cardHeight: CGFloat { cardWidth * size.height / max(size.width, 1) }
    /// overview_page_spacing
    private var spacing: CGFloat { 24 }
    private var step: CGFloat { cardWidth + spacing }
    private var centerY: CGFloat { (size.height - ui.navInset + ui.topStrip) / 2 + 12 }

    var body: some View {
        let tasks = ordered
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.55)
            if tasks.isEmpty {
                // recents_empty_message
                Text("No recent items")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size.width, height: size.height)
            } else {
                clearAllButton
                    .position(x: x(of: -1), y: centerY)
                    .opacity(Double(max(0, min(1, -position + 0.3))) + 0.2)
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    card(task)
                        .position(x: x(of: CGFloat(index)), y: centerY + offsetY(task))
                        .opacity(removing.contains(task.id) ? 0 : max(0.2, 1 + offsetY(task) / (cardHeight * 1.2)))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(drag(tasks))
        .onAppear {
            if !didAppear {
                didAppear = true
                position = CGFloat(max(0, tasks.count - 1))
            }
        }
        .onChange(of: tasks.count) { _, count in
            if position > CGFloat(count - 1) { withAnimation(.easeOut(duration: 0.2)) { position = CGFloat(max(0, count - 1)) } }
        }
    }

    private func x(of index: CGFloat) -> CGFloat { size.width / 2 + (index - position) * step }

    private func offsetY(_ task: AppTask) -> CGFloat {
        if removing.contains(task.id) { return -size.height }
        if let dragged, dragged.id == task.id { return min(dragged.dy, 40) }
        return 0
    }

    private func card(_ task: AppTask) -> some View {
        VStack(spacing: 12) {
            AppIconImage(app: task.app, size: 44)
                .frame(width: 44, height: 44)
            ZStack {
                if let snapshot = task.snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    Color(white: 0.2)
                    AppIconImage(app: task.app, size: 72).frame(width: 72, height: 72)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            // task_corner_radius
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.app.info.name)
        .accessibilityAddTraits(.isButton)
    }

    private var clearAllButton: some View {
        Text("Clear all")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.18)))
    }

    private func drag(_ tasks: [AppTask]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let t = value.translation
                if axis == nil && hypot(t.width, t.height) > 10 {
                    axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                    startPosition = position
                    if axis == .vertical, let task = task(at: value.startLocation, tasks) { dragged = (task.id, 0) }
                }
                switch axis {
                case .horizontal:
                    let raw = (startPosition ?? position) - t.width / step
                    position = rubberBand(raw, min: -1, max: CGFloat(max(0, tasks.count - 1)))
                case .vertical:
                    if let d = dragged { dragged = (d.id, t.height) }
                default: break
                }
            }
            .onEnded { value in
                defer { axis = nil; startPosition = nil }
                switch axis {
                case .horizontal:
                    let predicted = (startPosition ?? position) - value.predictedEndTranslation.width / step
                    let target = min(CGFloat(max(0, tasks.count - 1)), max(-1, predicted.rounded()))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { position = target }
                case .vertical:
                    guard let d = dragged else { return }
                    let fling = value.predictedEndTranslation.height
                    if d.dy < -cardHeight * 0.3 || fling < -cardHeight * 0.6, let task = tasks.first(where: { $0.id == d.id }) {
                        withAnimation(.easeIn(duration: 0.2)) { _ = removing.insert(d.id) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            ui.finish(task)
                            removing.remove(d.id)
                            if ui.tasks.isEmpty { ui.goHome() }
                        }
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragged = nil }
                default:
                    tap(at: value.location, tasks)
                }
            }
    }

    private func tap(at p: CGPoint, _ tasks: [AppTask]) {
        if let task = task(at: p, tasks) {
            ui.switchTo(task)
        } else if !tasks.isEmpty, abs(p.x - x(of: -1)) < 70, abs(p.y - centerY) < 30 {
            ui.clearAllTasks()
        } else {
            ui.goHome()
        }
    }

    private func task(at p: CGPoint, _ tasks: [AppTask]) -> AppTask? {
        let top = centerY - (cardHeight + 56) / 2, bottom = centerY + (cardHeight + 56) / 2
        guard p.y >= top, p.y <= bottom else { return nil }
        for (i, task) in tasks.enumerated() where abs(p.x - x(of: CGFloat(i))) <= cardWidth / 2 {
            return task
        }
        return nil
    }

    private func rubberBand(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        if v < lo { return lo - (lo - v) * 0.3 }
        if v > hi { return hi + (v - hi) * 0.3 }
        return v
    }
}
