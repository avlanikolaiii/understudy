import AppKit
import Combine
import SwiftUI

/// Borderless panel that sits over the MacBook notch. It can become key (so the
/// email field can take typing) without activating the app or stealing the menu bar.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
}

/// Places Understudy in the notch. On Macs without a notch, the same panel drops
/// down from the top center of the screen, below the menu bar.
@MainActor
final class NotchController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let state = NotchState()
    private let watch = WatchSession()
    private let panel: NotchPanel
    private var hosting: NSHostingView<NotchRootView>!
    private var bag = Set<AnyCancellable>()

    private let screen: NSScreen
    let hasNotch: Bool
    private let notchSize: CGSize

    init(model: AppModel) {
        self.model = model
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        screen = notched ?? NSScreen.main ?? screens[0]
        hasNotch = notched != nil
        if let s = notched {
            let left = s.auxiliaryTopLeftArea?.width ?? 0
            let right = s.auxiliaryTopRightArea?.width ?? 0
            notchSize = CGSize(width: max(s.frame.width - left - right, 120), height: s.safeAreaInsets.top)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 0, height: max(menuBar, 24))
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
        panel.delegate = self
        panel.setAccessibilityLabel("Understudy")

        let root = NotchRootView(model: model, state: state, watch: watch, notchSize: notchSize, hasNotch: hasNotch,
                                 onToggle: { [weak self] in self?.toggle() },
                                 onClose: { [weak self] in self?.collapse() })
        hosting = NSHostingView(rootView: root)
        panel.contentView = hosting

        // Re-fit the window whenever what's inside changes size (signed out ↔ signed in, messages).
        model.objectWillChange.merge(with: state.objectWillChange)
            .merge(with: watch.$phase.map { _ in () }, watch.$rules.map { _ in () })
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.fit(animated: true) }
            .store(in: &bag)

        fit(animated: false)
        if hasNotch { panel.orderFrontRegardless() }
    }

    // MARK: Open and close

    func toggle() {
        // The teaching interaction uses the configured shortcut (or the collapsed notch)
        // to stop watching and leave the captured sample available for inspection.
        if watch.isPlaying {
            watch.stop()
            expand()
        } else {
            state.expanded ? collapse() : expand()
        }
    }

    func expand() {
        guard !state.expanded else { panel.makeKey(); return }
        state.expanded = true
        fit(animated: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func collapse() {
        guard state.expanded else { return }
        state.expanded = false
        fit(animated: true)
        if !hasNotch { panel.orderOut(nil) }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere closes the panel, except while a sign-in sheet is open.
        if !model.busy { collapse() }
    }

    // MARK: Geometry

    private func fit(animated: Bool) {
        let size: CGSize
        if state.expanded {
            let fitted = hosting.fittingSize
            size = CGSize(width: max(fitted.width, 420), height: fitted.height)
        } else {
            let wing: CGFloat = state.hovering ? 44 : 30
            size = CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
        }
        let top = hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// The SwiftUI content of the notch window: a black shape that is a small pill when
/// collapsed and the full panel when expanded.
struct NotchRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchState
    @ObservedObject var watch: WatchSession
    let notchSize: CGSize
    let hasNotch: Bool
    let onToggle: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: state.expanded ? 22 : 12, bottomTrailingRadius: state.expanded ? 22 : 12)
                .fill(Color.black)
            if state.expanded {
                VStack(spacing: 0) {
                    Color.clear.frame(height: hasNotch ? notchSize.height : 0)
                    PanelView(model: model, watch: watch, onClose: onClose)
                }
            } else {
                HStack {
                    Spacer()
                    WatchPulse(active: watch.isPlaying)
                }
                .padding(.trailing, 12)
                .frame(height: notchSize.height)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                .accessibilityElement()
                .accessibilityLabel(watch.isPlaying ? "Understudy, simulated replay in progress" : "Understudy")
                .accessibilityHint("Opens the Understudy panel")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { onToggle() }
            }
        }
        .fixedSize(horizontal: false, vertical: state.expanded)
        .onHover { state.hovering = $0 }
    }
}
