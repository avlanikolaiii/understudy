import SwiftUI
import UnderstudyCore

/// How a list of steps is edited: delete, move up, retype (by index), add a step by hand
/// (`list` names which list, for `WorkspaceState.adding`), and re-record one step.
struct StepEdits {
    let delete: (Int) -> Void
    let moveUp: (Int) -> Void
    let retype: (String, Int) -> Void
    var ui: WorkspaceState?
    var list = ""
    var rerecord: ((Int) -> Void)?
    /// Sets a field of an App command step: (field, value, index).
    var setValue: ((String, String, Int) -> Void)?
}

/// A skill's steps: what each does, in which app, how it runs, and what needs the person.
/// With `edits`, each step can be deleted, moved up, or (for typing) changed.
struct StepListView: View {
    let steps: [SkillDefinition.Step]
    var edits: StepEdits?
    /// The recording the steps came from: each recorded step shows that moment of its video.
    var recording: UUID?
    @ObservedObject var frames = StepFrames.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if let ui = edits?.ui, ui.adding == .init(list: edits!.list, index: index) { AddStepView(ui: ui) }
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 22, height: 22).background(Color.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.intent).font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            Text(step.parameters["app"] ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(Self.how(step)).font(.caption).foregroundStyle(.secondary)
                            if step.effect.needsApproval {
                                Label("Needs your OK", systemImage: "hand.raised").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if step.executor == .unsupported, let reason = step.parameters["reason"] {
                            Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            if let bundle = step.parameters["reveal"] {
                                Button("Reopen \(step.parameters["app"] ?? "the app") for Understudy") {
                                    AX.reopenRevealed(bundle: bundle) { _ in }
                                }.controlSize(.small)
                            }
                        }
                        if let edits, let setValue = edits.setValue, step.parameters["action"] == "command",
                           let command = step.parameters["command"].flatMap(AppCommand.init(rawValue:)) {
                            ForEach(command.fields.filter { $0.options.isEmpty }, id: \.key) { field in
                                TextField(field.label, text: Binding(get: { step.parameters[field.key] ?? "" },
                                                                     set: { setValue(field.key, $0, index) }))
                                    .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 360)
                                    .accessibilityLabel("\(field.label) for step \(index + 1)")
                            }
                            if let problem = command.problem(step.parameters) {
                                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if let edits, step.parameters["action"] == "type" {
                            TextField("Text to type", text: Binding(get: { step.parameters["text"] ?? "" },
                                                                   set: { edits.retype($0, index) }))
                                .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 320)
                                .accessibilityLabel("Text for step \(index + 1)")
                        }
                    }
                    Spacer()
                    if let image = frames.image(recording: recording, at: step.parameters["t"]) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 120, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel("The recording at this step")
                    }
                    if let edits {
                        if let ui = edits.ui {
                            Button { ui.beginAdding(to: edits.list, at: index) } label: { Image(systemName: "plus") }
                                .buttonStyle(.borderless).help("Add a step before this one")
                                .accessibilityLabel("Add a step before step \(index + 1)")
                        }
                        if let rerecord = edits.rerecord {
                            Button { rerecord(index) } label: { Image(systemName: "record.circle") }
                                .buttonStyle(.borderless).help("Record this step again")
                                .accessibilityLabel("Record step \(index + 1) again")
                        }
                        Button { edits.moveUp(index) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).disabled(index == 0).help("Move up")
                            .accessibilityLabel("Move step \(index + 1) up")
                        Button(role: .destructive) { edits.delete(index) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete step")
                            .accessibilityLabel("Delete step \(index + 1)")
                    }
                }
                .padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            if let edits, let ui = edits.ui, AppCommand.replacingSpotifyClicks(in: steps, with: "spotify:track:x", name: "") != nil {
                SpotifyCommandOffer(ui: ui, list: edits.list)
            }
            if let edits, let ui = edits.ui {
                if ui.adding == .init(list: edits.list, index: steps.count) {
                    AddStepView(ui: ui)
                } else {
                    Button { ui.beginAdding(to: edits.list, at: steps.count) } label: { Label("Add step", systemImage: "plus") }
                }
            }
        }
    }

    /// How the step runs, in a few words.
    static func how(_ step: SkillDefinition.Step) -> String {
        switch step.parameters["action"] {
        case "activate": "Opens the app"
        case "press": "Presses it by name"
        case "focus": "Clicks into the field"
        case "type": "Types with the keyboard"
        case "keys": "Presses keys"
        case "command": "The app's own command"
        case "open": "Opens it"
        case "waitText", "waitSeconds": "Waits"
        default: step.executor == .unsupported ? "Can't run yet" : ""
        }
    }
}

/// Spotify's clicks depend on its window. Its own command plays by link, even minimized: this
/// reads what Spotify is playing now and offers that instead of the clicks.
struct SpotifyCommandOffer: View {
    @ObservedObject var ui: WorkspaceState
    let list: String
    @ObservedObject var reader = SpotifyNowPlaying.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Spotify can play this by its own command, without its window.", systemImage: "music.note")
                .font(.system(size: 12, weight: .semibold))
            Text("Start the song or album in Spotify, then use its command: the clicks on Spotify are replaced by one step that plays it by its link. You can paste an album or playlist link there instead (Share → Copy link).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(reader.reading ? "Reading Spotify…" : "Use Spotify's own command instead") {
                    reader.read { uri, name in ui.useSpotifyCommand(in: list, uri: uri, name: name) }
                }.controlSize(.small).disabled(reader.reading)
                if let problem = reader.problem { Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(10).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
