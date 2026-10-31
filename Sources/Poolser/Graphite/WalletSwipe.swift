import SwiftUI
import AppKit

/// Two-finger horizontal swipes on a trackpad or Magic Mouse, and ⌘← / ⌘→. SwiftUI has no
/// gesture for the swipes on macOS (a DragGesture needs the button held down), and a hidden
/// button's keyboard shortcut does not fire in the menu bar window, so this watches the window's
/// events. Horizontal swipes are consumed; vertical ones go on to the position list.
struct WalletSwipeMonitor: NSViewRepresentable {
    /// How far the fingers have moved, negative to the left.
    var onChange: (CGFloat) -> Void
    /// The distance when the fingers lift, 0 when the swipe was cancelled.
    var onEnd: (CGFloat) -> Void
    /// -1 for ⌘←, 1 for ⌘→.
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEnd: onEnd, onStep: onStep)
    }

    @MainActor
    final class Coordinator {
        private enum Axis { case undecided, horizontal, vertical }

        weak var view: NSView?
        var onChange: (CGFloat) -> Void
        var onEnd: (CGFloat) -> Void
        var onStep: (Int) -> Void
        private var monitor: Any?
        private var axis = Axis.undecided
        private var distance = CGSize.zero
        /// The momentum after a horizontal swipe would otherwise scroll the list.
        private var swallowsMomentum = false

        init(onChange: @escaping (CGFloat) -> Void, onEnd: @escaping (CGFloat) -> Void, onStep: @escaping (Int) -> Void) {
            self.onChange = onChange
            self.onEnd = onEnd
            self.onStep = onStep
        }

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    return event.type == .keyDown ? self.handleKey(event) : self.handle(event)
                }
            }
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            // Arrow keys also carry the function and numeric-pad flags.
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard let window = view?.window, event.window === window, modifiers == .command else { return event }
            switch event.keyCode {
            case 123: onStep(-1)
            case 124: onStep(1)
            default: return event
            }
            return nil
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            // A mouse wheel has no phases and no precise deltas; it only ever scrolls.
            guard let window = view?.window, event.window === window, event.hasPreciseScrollingDeltas else {
                return event
            }
            if !event.momentumPhase.isEmpty {
                return swallowsMomentum ? nil : event
            }
            guard !event.phase.isEmpty else { return event }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                axis = .undecided
                distance = .zero
                swallowsMomentum = false
            }
            // With natural scrolling the deltas follow the fingers; without it they are reversed.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            distance.width += event.scrollingDeltaX * sign
            distance.height += event.scrollingDeltaY
            if axis == .undecided, hypot(distance.width, distance.height) > 8 {
                axis = abs(distance.width) > abs(distance.height) * 1.5 ? .horizontal : .vertical
            }

            let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            guard axis == .horizontal else {
                if ended { axis = .undecided }
                return event
            }
            if ended {
                axis = .undecided
                swallowsMomentum = true
                onEnd(event.phase.contains(.cancelled) ? 0 : distance.width)
            } else {
                onChange(distance.width)
            }
            return nil
        }
    }
}
