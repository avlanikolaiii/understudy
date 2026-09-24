import AppKit
import ServiceManagement
import SwiftUI
import UnderstudyCore

/// "When it runs" for a skill: only when started, on a schedule, every few hours, when an app
/// opens, or when a file is added to a folder. Saved with the skill; runs on this Mac.
struct TriggerEditorView: View {
    @ObservedObject var ui: WorkspaceState
    @ObservedObject var scheduler: Scheduler
    let skill: Skill
    let save: (SkillDefinition.Trigger) -> Void

    private typealias Trigger = SkillDefinition.Trigger
    private var draft: Trigger { ui.triggerDraft }
    private var saved: Trigger { skill.definition.trigger }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When it runs").font(.system(size: 17, weight: .semibold))
            Picker("When it runs", selection: $ui.triggerDraft.kind) {
                Text("Only when I start it").tag(Trigger.Kind.manual)
                Text("On a schedule").tag(Trigger.Kind.schedule)
                Text("Every few hours").tag(Trigger.Kind.interval)
                Text("When an app opens").tag(Trigger.Kind.appOpened)
                Text("When a file is added to a folder").tag(Trigger.Kind.fileAdded)
            }.labelsHidden().frame(maxWidth: 320)
            switch draft.kind {
            case .schedule: schedule
            case .interval:
                Stepper("Every \(draft.everyHours ?? 1) hour\(draft.everyHours ?? 1 == 1 ? "" : "s")",
                        value: Binding(get: { draft.everyHours ?? 1 }, set: { ui.triggerDraft.everyHours = $0 }), in: 1...24)
                    .frame(maxWidth: 240)
            case .appOpened: appPicker
            case .fileAdded: folderPicker
            case .manual: EmptyView()
            }
            HStack(spacing: 12) {
                Button("Save") { save(ui.finishedTrigger(device: scheduler.device)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isComplete || ui.finishedTrigger(device: scheduler.device) == saved)
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            if draft.kind != .manual {
                Text("Triggered runs happen on this Mac while it's awake and Understudy is open. The notch counts down for 10 seconds first, and waits if you're typing or clicking.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LoginItemRow()
            }
        }
        .onAppear { ui.editTrigger(of: skill) }
        .onChange(of: skill.id) { ui.editTrigger(of: skill) }
    }

    private var status: String {
        if saved.kind == .manual { return "Now: only when you start it." }
        if saved.device != scheduler.device { return "Now: \(saved.summary), set on another Mac." }
        if let next = scheduler.nextRun(of: skill) {
            return "Now: \(saved.summary). Next: \(next.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Now: \(saved.summary)."
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Time", selection: Binding(get: {
                Calendar.current.date(from: DateComponents(hour: draft.hour ?? 9, minute: draft.minute ?? 0)) ?? Date()
            }, set: { date in
                ui.triggerDraft.hour = Calendar.current.component(.hour, from: date)
                ui.triggerDraft.minute = Calendar.current.component(.minute, from: date)
            }), displayedComponents: .hourAndMinute).frame(maxWidth: 200)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = (draft.weekdays ?? []).contains(day)
                    Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) { ui.toggleWeekday(day) }
                        .buttonStyle(.bordered).tint(on ? Color.accentColor : nil)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityValue(on ? "On" : "Off")
                }
                Text((draft.weekdays ?? []).isEmpty ? "Every day" : "").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appPicker: some View {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
        return Picker("App", selection: Binding(get: { draft.app ?? "" }, set: { bundle in
            ui.triggerDraft.app = bundle
            ui.triggerDraft.appName = apps.first { $0.0 == bundle }?.1
        })) {
            Text("Choose an open app").tag("")
            if let app = draft.app, !apps.contains(where: { $0.0 == app }) { Text(draft.appName ?? app).tag(app) }
            ForEach(apps, id: \.0) { Text($0.1).tag($0.0) }
        }.frame(maxWidth: 320)
    }

    private var folderPicker: some View {
        HStack {
            Button("Choose folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Watch this folder"
                if panel.runModal() == .OK, let url = panel.url { ui.triggerDraft.folder = url.path }
            }
            Text(draft.folder ?? "No folder yet").font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Opening Understudy at login, so triggers keep working after a restart. macOS asks and shows it
/// in Login Items; the person can turn it off there too.
private struct LoginItemRow: View {
    var body: some View {
        let service = SMAppService.mainApp
        HStack {
            Text(service.status == .enabled ? "Understudy opens at login." : "Understudy doesn't open at login yet.")
                .font(.caption).foregroundStyle(.secondary)
            Button(service.status == .enabled ? "Turn off" : "Open at login") {
                do {
                    if service.status == .enabled { try service.unregister() } else { try service.register() }
                } catch {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }.controlSize(.small)
        }
    }
}
