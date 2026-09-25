import AppKit
import Combine
import UnderstudyCore

/// A keyboard shortcut per skill (e.g. ⌥1), kept on this Mac. Pressing it runs the skill at once:
/// the person asked for it directly. Clashes with the main shortcut or another skill are refused.
@MainActor
final class SkillShortcuts: ObservableObject {
    typealias Installer = (KeyboardShortcut, @escaping () -> Void) throws -> AnyObject
    static let preferenceKey = "skillShortcuts.v1"

    @Published private(set) var shortcuts: [UUID: KeyboardShortcut] = [:]
    @Published private(set) var error: (skill: UUID, message: String)?

    private let defaults: UserDefaults
    private let install: Installer
    private let reserved: () -> [KeyboardShortcut]
    private var registrations: [UUID: AnyObject] = [:]
    private var run: (UUID) -> Void = { _ in }

    /// `reserved` are Understudy's own shortcuts (Watch, the quick launcher), which a skill can't take.
    init(defaults: UserDefaults = .standard, reserved: @escaping () -> [KeyboardShortcut],
         install: @escaping Installer = { try HotKey(shortcut: $0, action: $1) }) {
        self.defaults = defaults; self.reserved = reserved; self.install = install
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode([UUID: KeyboardShortcut].self, from: data) {
            shortcuts = saved
        }
    }

    /// Registers the shortcuts of skills that still exist; `run` is called with the skill's id.
    func start(skills: [UUID], run: @escaping (UUID) -> Void) {
        self.run = run
        for (id, shortcut) in shortcuts where registrations[id] == nil && skills.contains(id) {
            registrations[id] = try? install(shortcut) { [weak self] in self?.run(id) }
        }
        for id in registrations.keys where !skills.contains(id) { remove(for: id) }
    }

    @discardableResult
    func set(_ shortcut: KeyboardShortcut, for skill: UUID) -> Bool {
        error = nil
        if let reason = shortcut.validationError { error = (skill, reason); return false }
        let same = { (other: KeyboardShortcut) in other.keyCode == shortcut.keyCode && other.modifiers == shortcut.modifiers }
        if reserved().contains(where: same) { error = (skill, "Understudy uses that shortcut (Watch or the quick launcher). Choose another."); return false }
        if shortcuts.contains(where: { $0.key != skill && same($0.value) }) {
            error = (skill, "Another skill uses that shortcut. Choose another."); return false
        }
        if shortcuts[skill] == shortcut, registrations[skill] != nil { return true }
        // macOS won't register a combination twice, so the old one is released first and put back on failure.
        registrations[skill] = nil
        do {
            registrations[skill] = try install(shortcut) { [weak self] in self?.run(skill) }
            shortcuts[skill] = shortcut
            save()
            return true
        } catch {
            if let previous = shortcuts[skill] { registrations[skill] = try? install(previous) { [weak self] in self?.run(skill) } }
            self.error = (skill, error.localizedDescription)
            return false
        }
    }

    func remove(for skill: UUID) {
        registrations[skill] = nil
        shortcuts[skill] = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: Self.preferenceKey) }
    }
}
