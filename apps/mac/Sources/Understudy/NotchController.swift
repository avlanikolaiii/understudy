import AppKit
import Combine
import SwiftUI

/// Borderless panel over the MacBook notch. It never takes keyboard focus; typing
/// happens in the main window.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The first click on the non-activating panel should act, not just focus it.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Places Understudy in the notch. On Macs without a notch, the strip drops down from
/// the top center of the screen, below the menu bar, only while something is happening.
///
/// The window itself never animates. It grows at once to fit the strip, SwiftUI springs
/// the black shape open inside it, and the window shrinks back only after the shape has
/// finished closing, so clicks outside the shape reach the apps underneath.
@MainActor
final class NotchController: NSObject {
    private let activity: NotchActivity
    private let state = NotchState()
    private let panel: NotchPanel
    private var hosting: NotchHostingView<NotchLiveView>!
    private var bag = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?
    private var handleTap: () -> Void = {}
    private var hideWork: DispatchWorkItem?

    private let screen: NSScreen
    let hasNotch: Bool
    private let notchSize: CGSize

    init(activity: NotchActivity, onTap: @escaping (PrototypePage) -> Void) {
        self.activity = activity
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        screen = notched ?? NSScreen.main ?? screens[0]
        hasNotch = notched != nil
        if let s = notched {
            let left = s.auxiliaryTopLeftArea?.width ?? 0
            let right = s.auxiliaryTopRightArea?.width ?? 0
            notchSize = CGSize(width: max(s.frame.width - left - right, 120), height: s.safeAreaInsets.top)
        } else {
            notchSize = CGSize(width: 0, height: 30)
        }
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.setAccessibilityLabel("Understudy")
        // Keep the strip out of Watch's screen recording: it shows the recording, not the task.
        panel.sharingType = .none

        handleTap = { [weak activity] in
            guard let activity else { return }
            let page = activity.page
            activity.dismiss()
            onTap(page)
        }
        let root = NotchLiveView(activity: activity, state: state, notchSize: notchSize, hasNotch: hasNotch,
                                 onTap: { [weak self] in self?.handleTap() })
        hosting = NotchHostingView(rootView: root)
        panel.contentView = hosting

        activity.$mode.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] mode in self?.modeChanged(mode) }
            .store(in: &bag)
        // Re-fit whenever what's inside changes size (rows arriving, hover).
        activity.objectWillChange.merge(with: state.objectWillChange)
            .debounce(for: .milliseconds(15), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.fit() }
            .store(in: &bag)

        fit()
        if hasNotch { panel.orderFrontRegardless() }
    }

    /// Whether the strip is open. Read by the self-test.
    var isExpanded: Bool { state.expanded }

    /// The same action as clicking the notch. Used by the self-test.
    func tap() { handleTap() }

    /// The strip as SwiftUI draws it right now, at the panel's size. Used by the self-test,
    /// because copying a non-opaque panel's backing store doesn't match what's on screen.
    func render() -> NSBitmapImageRep? {
        let view = NotchLiveView(activity: activity, state: state, notchSize: notchSize, hasNotch: hasNotch, onTap: {})
            .frame(width: panel.frame.width, height: panel.frame.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func modeChanged(_ mode: NotchActivity.Mode) {
        hideWork?.cancel()
        setExpanded(mode != .idle)
        if mode == .stopped {
            // A stopped Watch waits in the main window. Tuck the strip away after a moment.
            let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }
    }

    private func setExpanded(_ open: Bool) {
        guard state.expanded != open else { return }
        if open && !hasNotch { panel.orderFrontRegardless() }
        withAnimation(reduceMotion ? nil : NotchStyle.spring) { state.expanded = open }
        fit()
    }

    // MARK: Geometry

    private func fit() {
        hosting.layoutSubtreeIfNeeded()
        let target = hosting.fittingSize
        let current = panel.frame.size
        shrinkWork?.cancel()
        if target.width >= current.width && target.height >= current.height {
            place(target)
            return
        }
        // Grow now in whichever direction grows; shrink once the close animation is done.
        place(CGSize(width: max(target.width, current.width), height: max(target.height, current.height)))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.place(self.hosting.fittingSize)
            if !self.hasNotch && !self.state.expanded { self.panel.orderOut(nil) }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.6), execute: work)
    }

    private func place(_ size: CGSize) {
        let top = hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: top - size.height,
                           width: size.width.rounded(.up), height: size.height.rounded(.up))
        if frame != panel.frame { panel.setFrame(frame, display: true, animate: false) }
    }
}
