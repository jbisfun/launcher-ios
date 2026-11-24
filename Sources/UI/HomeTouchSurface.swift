import SwiftUI
import UIKit

/// The home screen's own touch handling (MainActivity.onTouchEvent): raw touches with their
/// release velocity, so swipes, flings, long presses and drags all go through one state machine.
struct HomeTouchSurface: UIViewRepresentable {
    let controller: HomeController

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = false
        v.controller = controller
        return v
    }

    func updateUIView(_ v: TouchView, context: Context) { v.controller = controller }

    final class TouchView: UIView {
        weak var controller: HomeController?
        private weak var tracked: UITouch?
        private var samples: [(CGPoint, TimeInterval)] = []

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard tracked == nil, let t = touches.first else { return }
            tracked = t
            let p = t.location(in: self)
            samples = [(p, t.timestamp)]
            controller?.touchBegan(p)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = tracked, touches.contains(t) else { return }
            let p = t.location(in: self)
            samples.append((p, t.timestamp))
            if samples.count > 6 { samples.removeFirst() }
            controller?.touchMoved(p)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = tracked, touches.contains(t) else { return }
            finish(t, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = tracked, touches.contains(t) else { return }
            finish(t, cancelled: true)
        }

        private func finish(_ t: UITouch, cancelled: Bool) {
            let p = t.location(in: self)
            samples.append((p, t.timestamp))
            tracked = nil
            controller?.touchEnded(p, velocity: Self.velocity(samples), cancelled: cancelled)
            samples = []
        }

        /// Points per second over the last ~100 ms (VelocityTracker).
        static func velocity(_ samples: [(CGPoint, TimeInterval)]) -> CGVector {
            guard let last = samples.last else { return .zero }
            let recent = samples.filter { last.1 - $0.1 <= 0.1 }
            guard let first = recent.first, last.1 - first.1 > 0.005 else { return .zero }
            let dt = last.1 - first.1
            return CGVector(dx: (last.0.x - first.0.x) / dt, dy: (last.0.y - first.0.y) / dt)
        }
    }
}

/// Tap and long press on a drawer / widget list cell, done in UIKit so the enclosing scroll view
/// keeps scrolling and the long press can turn into a drag that continues on the home screen.
/// Long press points are in window coordinates (the home screen fills the window).
struct TouchCatcher: UIViewRepresentable {
    var onTap: () -> Void
    var onLongPress: (UIGestureRecognizer.State, CGPoint, CGRect) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.long(_:)))
        long.minimumPressDuration = 0.45
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: long)
        v.addGestureRecognizer(long)
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap, onLongPress: onLongPress) }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onLongPress: (UIGestureRecognizer.State, CGPoint, CGRect) -> Void

        init(onTap: @escaping () -> Void, onLongPress: @escaping (UIGestureRecognizer.State, CGPoint, CGRect) -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        @objc func tap() { onTap() }

        @objc func long(_ g: UILongPressGestureRecognizer) {
            let frame = g.view.map { $0.convert($0.bounds, to: nil) } ?? .zero
            onLongPress(g.state, g.location(in: nil), frame)
        }
    }
}
