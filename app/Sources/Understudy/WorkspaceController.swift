import AppKit
import SwiftUI

@MainActor
final class WorkspaceController: NSObject {
    private let window: NSWindow
    private let store = PrototypeStore()
    private let ui = WorkspaceState()
    private let watch: WatchSession

    init(watch: WatchSession, openSettings: @escaping () -> Void) {
        self.watch = watch
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Understudy"
        window.subtitle = "Simulated prototype"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 600)
        window.contentViewController = NSHostingController(rootView: PrototypeView(store: store, ui: ui, watch: watch, openSettings: openSettings))
        window.toolbarStyle = .unified
        window.center()
        window.setFrameAutosaveName("UnderstudyWorkspace")
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func teachSkill() {
        ui.showTeaching(watch: watch)
        show()
    }

}
