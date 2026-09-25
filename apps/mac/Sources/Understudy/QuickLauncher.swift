import AppKit
import Combine
import SwiftUI
import UnderstudyCore

/// The quick launcher: a shortcut (⇧⌥Space) opens a search box over any app; type part of a
/// skill's name, pick it with ↑↓, and ↩ runs it at once (the person asked for it, as with a
/// skill's own shortcut). A skill with `{values}` asks for them first, filled with its defaults.
@MainActor
final class LauncherModel: ObservableObject {
    enum Entry: Equatable {
        case skill(Skill)
        case teach, openApp

        var title: String {
            switch self {
            case .skill(let skill): skill.name
            case .teach: "Teach a skill"
            case .openApp: "Open Understudy"
            }
        }
    }

    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    /// The skill whose values are being asked for, and the values.
    @Published private(set) var asking: Skill?
    @Published var values: [String: String] = [:]
    @Published private(set) var isOpen = false

    static let limit = 7
    let library: SkillLibrary
    let shortcuts: SkillShortcuts
    var run: (Skill, [String: String]) -> Void = { _, _ in }
    var teach: () -> Void = {}
    var openApp: () -> Void = {}
    var onOpenChange: (Bool) -> Void = { _ in }

    init(library: SkillLibrary, shortcuts: SkillShortcuts) {
        self.library = library
        self.shortcuts = shortcuts
    }

    /// Skills with steps that fit what's typed, best first, then the two ways into the app.
    var entries: [Entry] {
        let skills = library.skills.filter { !$0.definition.steps.isEmpty }
        let ranked = Matching.launcherRanked(query, skills.map(\.name)).prefix(Self.limit).map { Entry.skill(skills[$0]) }
        let extras = [Entry.teach, .openApp].filter { Matching.launcherScore(query, $0.title) != nil }
        return ranked + extras
    }

    func caption(_ entry: Entry) -> String {
        switch entry {
        case .skill(let skill):
            if let shortcut = shortcuts.shortcuts[skill.id] { return shortcut.display.replacingOccurrences(of: " ", with: "") }
            let trigger = skill.definition.trigger
            return trigger.kind == .manual ? "\(skill.definition.steps.count) steps" : trigger.summary
        case .teach: return "Record a new skill"
        case .openApp: return "Skills, receipts, settings"
        }
    }

    func open() {
        query = ""; selection = 0; asking = nil; values = [:]
        isOpen = true
        onOpenChange(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        asking = nil
        onOpenChange(false)
    }

    func move(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    /// ↩: run the selected skill, or ask for its values first; with values asked, run it.
    func enter() {
        if let skill = asking {
            close()
            return run(skill, values)
        }
        let list = entries
        guard list.indices.contains(selection) else { return }
        switch list[selection] {
        case .skill(let skill):
            if skill.variables.isEmpty {
                close()
                run(skill, [:])
            } else {
                values = skill.defaultValues
                asking = skill
            }
        case .teach: close(); teach()
        case .openApp: close(); openApp()
        }
    }

    /// Esc: back from the values to the list, or close.
    func escape() {
        if asking != nil { asking = nil } else { close() }
    }
}

/// A borderless panel that takes the keyboard without making Understudy the active app, like Spotlight.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickLauncher: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let panel: LauncherPanel
    private var hosting: NSHostingView<LauncherView>!
    private var bag = Set<AnyCancellable>()

    init(model: LauncherModel) {
        self.model = model
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setAccessibilityLabel("Run a skill")
        hosting = NSHostingView(rootView: LauncherView(model: model))
        panel.contentView = hosting
        model.onOpenChange = { [weak self] open in open ? self?.show() : self?.panel.orderOut(nil) }
        // The window follows the list's height, keeping its top edge where it is.
        model.objectWillChange.debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.fit() }
            .store(in: &bag)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { model.isOpen ? model.close() : model.open() }

    private func show() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = fittedSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - screen.frame.height * 0.14,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private var fittedSize: CGSize {
        hosting.layoutSubtreeIfNeeded()
        return CGSize(width: 640, height: max(hosting.fittingSize.height, 100))
    }

    private func fit() {
        guard panel.isVisible else { return }
        let size = fittedSize, top = panel.frame.maxY
        guard size.height != panel.frame.height else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Clicking anywhere else closes it, as Spotlight does.
    func windowDidResignKey(_ notification: Notification) { model.close() }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let skill = model.asking {
                valuesForm(skill)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(NotchStyle.muted)
                    LauncherField(text: $model.query, placeholder: "Run a skill…", size: 20, focused: true,
                                  onMove: model.move, onEnter: model.enter, onEscape: model.escape)
                        .frame(height: 28)
                    Text("⇧⌥Space").font(.system(size: 11, design: .monospaced)).foregroundStyle(NotchStyle.muted)
                }
                .padding(.horizontal, 18).frame(height: 58)
                Divider().overlay(Color.white.opacity(0.08))
                results
            }
            footer
        }
        .frame(width: 640, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .foregroundStyle(NotchStyle.ink)
        .environment(\.colorScheme, .dark)
    }

    private var results: some View {
        let entries = model.entries
        return VStack(spacing: 2) {
            if entries.isEmpty {
                Text("No skill is called that.").font(.system(size: 13)).foregroundStyle(NotchStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 44)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Button {
                    model.selection = index
                    model.enter()
                } label: {
                    HStack(spacing: 12) {
                        icon(entry).frame(width: 26, height: 26)
                        Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(model.caption(entry)).font(.system(size: 11, design: .monospaced)).foregroundStyle(NotchStyle.muted).lineLimit(1)
                        if index == model.selection {
                            Text("↩").font(.system(size: 12, weight: .semibold)).foregroundStyle(NotchStyle.highlight)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(index == model.selection ? 0.1 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.title)
                .accessibilityHint(model.caption(entry))
            }
        }
        .padding(8)
    }

    @ViewBuilder private func icon(_ entry: LauncherModel.Entry) -> some View {
        switch entry {
        case .skill(let skill): NotchAppIcon(bundle: skill.definition.steps.lazy.compactMap(\.target.app).first)
        case .teach: Image(systemName: "record.circle").font(.system(size: 17)).foregroundStyle(NotchStyle.highlight)
        case .openApp: Image(systemName: "macwindow").font(.system(size: 16)).foregroundStyle(NotchStyle.ink)
        }
    }

    private func valuesForm(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NotchAppIcon(bundle: skill.definition.steps.lazy.compactMap(\.target.app).first).frame(width: 26, height: 26)
                Text("Run \(skill.name)").font(.system(size: 16, weight: .semibold))
            }
            ForEach(Array(skill.variables.enumerated()), id: \.element) { index, name in
                HStack(spacing: 12) {
                    Text(name).font(.system(size: 12, design: .monospaced)).foregroundStyle(NotchStyle.muted).frame(width: 110, alignment: .trailing)
                    LauncherField(text: Binding(get: { model.values[name] ?? "" }, set: { model.values[name] = $0 }),
                                  placeholder: "{\(name)}", size: 14, focused: index == 0,
                                  onMove: { _ in }, onEnter: model.enter, onEscape: model.escape)
                        .frame(height: 22)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
            }
        }
        .padding(18)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.asking != nil {
                hint("↩", "run"); hint("⇥", "next value"); hint("esc", "back")
            } else {
                hint("↑↓", "choose"); hint("↩", "run"); hint("esc", "close")
            }
            Spacer()
        }
        .font(.system(size: 11)).foregroundStyle(NotchStyle.muted)
        .padding(.horizontal, 18).frame(height: 34)
        .background(Color.white.opacity(0.04))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
            Text(text)
        }
    }
}

/// A plain AppKit text field for the launcher: it takes the keyboard when shown, and hands
/// ↑ ↓ ↩ and Esc to the launcher instead of moving the cursor.
struct LauncherField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let size: CGFloat
    let focused: Bool
    let onMove: (Int) -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: size, weight: size > 16 ? .regular : .medium)
        field.textColor = NSColor(white: 0.95, alpha: 1)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor(white: 1, alpha: 0.35), .font: NSFont.systemFont(ofSize: size)])
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        if focused { DispatchQueue.main.async { field.window?.makeFirstResponder(field) } }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherField
        init(parent: LauncherField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onEnter()
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape()
            default: return false
            }
            return true
        }
    }
}
