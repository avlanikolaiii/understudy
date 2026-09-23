import AppKit
import Combine
import SwiftUI

/// The main Understudy window. It shares every object with the notch, so there is one app state.
@MainActor
final class WorkspaceController: NSObject {
    private let window: NSWindow
    private let ui: WorkspaceState
    private let watch: WatchSession
    private var bag = Set<AnyCancellable>()

    init(auth: AppModel, library: SkillLibrary, ui: WorkspaceState, watch: WatchSession, activity: NotchActivity,
         openSettings: @escaping () -> Void) {
        self.ui = ui
        self.watch = watch
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Understudy"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 600)
        window.contentViewController = NSHostingController(rootView: MainWindowView(
            auth: auth, library: library, ui: ui, watch: watch, activity: activity, openSettings: openSettings))
        window.toolbarStyle = .unified
        window.center()
        window.setFrameAutosaveName("UnderstudyWorkspace")
        library.$mode.receive(on: RunLoop.main)
            .sink { [weak self, weak library] _ in self?.window.subtitle = library?.modeText ?? "" }
            .store(in: &bag)
    }

    func show(_ page: PrototypePage? = nil) {
        if let page {
            if page == .teach { ui.showTeaching(watch: watch) } else { ui.page = page }
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func teachSkill() {
        show(.teach)
    }
}
