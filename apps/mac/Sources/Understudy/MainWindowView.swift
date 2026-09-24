import SwiftUI

/// The one main window: teaching, skills, receipts, and the account. The notch is its live companion.
struct MainWindowView: View {
    @ObservedObject var auth: AppModel
    @ObservedObject var library: SkillLibrary
    @ObservedObject var ui: WorkspaceState
    @ObservedObject var watch: WatchSession
    @ObservedObject var activity: NotchActivity
    let runner: RunController
    let scheduler: Scheduler
    var openSettings: () -> Void = {}

    private var activeSkill: Skill { ui.activeSkill(in: library) }
    private var receipt: Receipt? {
        library.receipts.first(where: { $0.id == ui.selectedReceipt }) ?? library.receipts.first
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $ui.page) {
                Section("Workspace") {
                    ForEach(PrototypePage.workspace, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
                Section("Account") {
                    Label(library.mode == .sample ? "Sample mode" : "Your account", systemImage: PrototypePage.account.symbol)
                        .tag(PrototypePage.account)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 270)
            .safeAreaInset(edge: .bottom) {
                Label(library.mode == .sample ? "Saved on this Mac" : "Saved to your account",
                      systemImage: library.mode == .sample ? "internaldrive" : "person.crop.circle.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch ui.page ?? .home {
                        case .home: home
                        case .teach: teach
                        case .skills: skills
                        case .results: results
                        case .account: AccountView(auth: auth, library: library)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let notice = library.notice {
                    Divider()
                    HStack {
                        Text(notice).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button("Dismiss") { library.notice = nil }
                    }.padding(12)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { ui.showTeaching(watch: watch) } label: {
                    Label("Teach a skill", systemImage: "plus")
                }.help("Start or resume teaching a skill")
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }.help("Change keyboard shortcut")
            }
        }
        .onReceive(watch.$phase) { phase in
            if phase == .watching { ui.page = .teach; ui.teachingStep = 1 }
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("Make room for your real work.", "Teach a routine. Review what it learned. See the result.")
            VStack(alignment: .leading, spacing: 18) {
                HStack { badge("START HERE"); Spacer(); Image(systemName: "sparkles").foregroundStyle(Color.accentColor) }
                Text("Show it once. Then hand it off.").font(.title.weight(.semibold))
                Text("Do a task once while Understudy records your screen and notes each step. Rehearsals and receipts still use fictional sample data, and nothing is connected or sent.")
                    .font(.system(size: 14)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    primary("Teach a skill", symbol: "record.circle") { ui.showTeaching(watch: watch) }
                    Button("Explore sample skill") { ui.page = .skills }.buttonStyle(.bordered)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor.opacity(0.25)))
            HStack(spacing: 14) {
                stat("\(library.skills.count)", library.mode == .sample ? "Skills on this Mac" : "Skills in your account", "square.stack.3d.up")
                stat("\(library.receipts.count)", "Rehearsal receipts", "theatermasks")
                stat("0", "Connected apps", "link")
            }
            Text("A handoff you can inspect").font(.system(size: 17, weight: .semibold))
            step("1", "Show your process", "Record the task once while Understudy watches, and add notes as you go.")
            step("2", "Try a different case", "Switch between complete inputs and a missing figure.")
            step("3", "See what happened", "Read the sample report, its status, and the limits of its evidence.")
        }
    }

    private var teach: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Teach a skill", "Start Watch here or from the notch, then do the task as you usually do. Learning from the recording comes next; the review below uses a sample procedure.")
            HStack {
                ForEach(0..<3) { i in
                    Text(["1  Describe", "2  Show", "3  Review"][i])
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ui.teachingStep == i ? Color.accentColor : Color.secondary)
                    if i < 2 { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.secondary); Spacer() }
                }
            }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            if ui.teachingStep == 0 {
                field("Task name", text: $ui.skillName)
                field("Client or project", text: $ui.clientName)
                Text("What should it remember?").font(.system(size: 13, weight: .semibold))
                TextEditor(text: $ui.rules).font(.body).frame(height: 100).padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                    .accessibilityLabel("Workflow notes")
                Text("Notes are saved with the skill. They aren't applied yet.")
                    .font(.system(size: 12)).foregroundStyle(Color.secondary)
                primary(watch.isPresented ? "Resume Watch" : "Start Watch", symbol: "record.circle") { ui.startWatch(watch) }
                    .disabled(ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if ui.teachingStep == 1 {
                WorkspaceWatchView(session: watch, onReview: { ui.reviewWatch(watch) })
                Button("Back to description") { ui.teachingStep = 0 }
            } else {
                badge(ui.draftSteps.isEmpty ? "NO STEPS RECORDED · NOTES ONLY" : "YOUR STEPS · FROM YOUR RECORDING")
                field("Skill name", text: $ui.skillName)
                field("Client or project", text: $ui.clientName)
                if let recording = watch.recording {
                    detail("YOUR RECORDING", "\(recording.actions.count) actions over \(Int(recording.duration.rounded())) seconds\(recording.video == nil ? "" : ", with screen video"). Saved on this Mac.")
                }
                if ui.draftSteps.isEmpty {
                    Text("Nothing was recorded to replay. Record again, or save the notes on their own.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Understudy replays these steps exactly as you did them, without the mouse. Delete anything you don't want, like switching back to Understudy.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    StepListView(steps: ui.draftSteps, edits: StepEdits(delete: ui.deleteStep, moveUp: ui.moveStepUp,
                                                                        retype: { ui.setTypedText($0, at: $1) }))
                }
                detail("YOUR NOTES", ui.rules.isEmpty ? "No additional notes." : ui.rules)
                HStack {
                    Button("Back") { ui.teachingStep = 1 }
                    primary("Save skill", symbol: "checkmark") {
                        ui.saveReviewedSkill(library: library, watch: watch, activity: activity)
                    }
                    .disabled(!ui.canSaveSkill)
                }
            }
        }
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Your skills", library.mode == .sample ? "Sample mode: saved on this Mac. Sign in to keep them in your account." : "Saved to your account.")
            ForEach(library.skills) { skill in
                Button { ui.selectedSkill = skill } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(skill.name).font(.system(size: 15, weight: .semibold))
                            Text(skill.client).font(.system(size: 12)).foregroundStyle(Color.secondary)
                        }
                        Spacer(); Text(skill.isSample ? "Sample" : skill.definition.steps.isEmpty ? "No steps yet" : "\(skill.definition.steps.count) steps")
                            .font(.caption).foregroundStyle(.secondary)
                        if activeSkill.id == skill.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(activeSkill.id == skill.id ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor)))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider()
            if !activeSkill.isSample {
                HStack {
                    Text(activeSkill.name).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    if ui.editing != activeSkill.id {
                        Button { ui.beginEdit(activeSkill) } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete(activeSkill) } label: { Label("Delete", systemImage: "trash") }
                            .disabled(runner.isRunning && runner.skill?.id == activeSkill.id)
                    }
                }
            }
            if ui.editing == activeSkill.id {
                editForm(activeSkill)
            } else if !activeSkill.definition.steps.isEmpty {
                RunPanelView(runner: runner, skill: activeSkill, openReceipts: { ui.selectedReceipt = runner.lastReceipt; ui.page = .results })
                TriggerEditorView(ui: ui, scheduler: scheduler, skill: activeSkill) { trigger in
                    ui.saveTrigger(trigger, of: activeSkill, library: library)
                }
                Text("Steps").font(.system(size: 17, weight: .semibold))
                StepListView(steps: activeSkill.definition.steps)
                if let latest = watch.latestRecording(), latest.id != activeSkill.definition.recording {
                    HStack {
                        Button("Use latest recording (\(latest.startedAt.formatted(date: .omitted, time: .shortened)))") {
                            ui.addStepsFromLatestRecording(to: activeSkill, library: library, watch: watch)
                        }
                        Text("Replaces these steps with your newest take. Notes and schedule stay.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if !activeSkill.isSample {
                Text("\(activeSkill.name) has no steps yet").font(.system(size: 20, weight: .semibold))
                Text("It was saved before Understudy could turn recordings into steps. Use your latest recording, or teach it again.")
                    .font(.system(size: 13)).foregroundStyle(Color.secondary)
                primary("Create steps from latest recording", symbol: "wand.and.stars") {
                    ui.addStepsFromLatestRecording(to: activeSkill, library: library, watch: watch)
                }.disabled(watch.latestRecording() == nil)
            }
            if activeSkill.definition.steps.isEmpty { rehearsal }
        }
    }

    /// Edit skill: name, client, notes, and the steps. Its schedule is set under When it runs.
    private func editForm(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Skill name", text: $ui.editName)
            field("Client or project", text: $ui.editClient)
            Text("Notes").font(.system(size: 13, weight: .semibold))
            TextEditor(text: $ui.editNotes).font(.body).frame(height: 80).padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Skill notes")
            if !ui.editSteps.isEmpty {
                Text("Steps").font(.system(size: 13, weight: .semibold))
                StepListView(steps: ui.editSteps, edits: StepEdits(
                    delete: { WorkspaceState.deleteStep(at: $0, in: &ui.editSteps) },
                    moveUp: { WorkspaceState.moveStepUp(at: $0, in: &ui.editSteps) },
                    retype: { WorkspaceState.setTypedText($0, at: $1, in: &ui.editSteps) }))
            }
            HStack {
                Button("Cancel") { ui.cancelEdit() }
                primary("Save changes", symbol: "checkmark") { ui.saveEdit(of: skill, library: library) }
                    .disabled(!ui.canSaveEdit)
            }
        }
    }

    /// Asks before deleting; receipts of past runs stay.
    private func confirmDelete(_ skill: Skill) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(skill.name)”?"
        alert.informativeText = "Its steps and schedule are deleted. Receipts of past runs stay."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ui.deleteSkill(skill, library: library, runner: runner)
        }
    }

    /// The sample rehearsal, for skills without recorded steps.
    private var rehearsal: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Rehearse \(activeSkill.name)").font(.system(size: 20, weight: .semibold))
            Text("Watch it rehearse in the notch. It uses fixed sample inputs, doesn't test AI learning, and doesn't connect to your accounts.")
                .font(.system(size: 13)).foregroundStyle(Color.secondary)
            Picker("Sample inputs", selection: $ui.scenario) {
                ForEach(SampleCase.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            detail("WHAT CHANGES", ui.scenario == .complete ? "All sample figures are present. The report is ready for your review." : "Video spend is absent. Total spend and cost per lead stay missing; sharing is blocked.")
            HStack(spacing: 12) {
                primary("Rehearse sample", symbol: "play.fill") {
                    ui.rehearseActiveSkill(library: library, activity: activity)
                }.disabled(activity.isRehearsing || !library.canRehearse || runner.isRunning)
                if activity.isRehearsing {
                    ProgressView().controlSize(.small)
                    Text("Rehearsing in the notch (read-only)…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Receipts", "What happened, what was checked, and what still needs you.")
            if let receipt {
                if library.receipts.count > 1 {
                    Picker("Rehearsal", selection: Binding(get: { receipt.id }, set: { ui.selectedReceipt = $0 })) {
                        ForEach(library.receipts) { item in Text("\(item.isRun ? item.skillName : item.client) · \(item.status) · \(item.date.formatted(date: .omitted, time: .standard))").tag(item.id) }
                    }
                }
                if receipt.isRun { runReceipt(receipt) } else { sampleReceipt(receipt) }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.rectangle").font(.system(size: 40)).foregroundStyle(Color.secondary)
                    Text("Your first receipt starts with a run or a rehearsal.").font(.system(size: 18, weight: .medium))
                    primary("Go to your skills", symbol: "arrow.right") { ui.page = .skills }
                }.frame(maxWidth: .infinity).padding(.vertical, 70)
            }
        }
    }

    /// A real run: each step's status, and its evidence, kept apart.
    private func runReceipt(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    badge("RUN RECEIPT · \(receipt.date.formatted(date: .abbreviated, time: .shortened))")
                    Text(receipt.status).font(.system(size: 26, weight: .semibold))
                    Text(receipt.skillName).font(.system(size: 13)).foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemName: receipt.readyToSend ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 32)).foregroundStyle(receipt.readyToSend ? Color.accentColor : Color.orange)
            }
            ForEach(Array(receipt.steps.enumerated()), id: \.offset) { index, step in
                evidence("\(index + 1). \(step.step)", step.status, step.evidence)
            }
            Button("Back to skills") { ui.page = .skills }.buttonStyle(.bordered)
        }
    }

    private func sampleReceipt(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        badge("SAMPLE RECEIPT")
                        Text(receipt.status).font(.system(size: 26, weight: .semibold))
                        Text(receipt.client).font(.system(size: 13)).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Image(systemName: receipt.missingSpend ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 32)).foregroundStyle(receipt.missingSpend ? Color.orange : Color.accentColor)
                }
                evidence("Sample report", receipt.missingSpend ? "Incomplete" : "Created locally", "Generated from fixed fictional inputs, not an observed workflow.")
                evidence("Figures", receipt.missingSpend ? "Missing spend" : "Sample only", receipt.missingSpend ? "Total spend and cost per lead are withheld. No estimate was substituted." : "Predefined sample figures. No external source was queried or verified.")
                evidence("Connected apps", "Untouched", "No connections or external writes are implemented in this demo.")
                evidence("Sharing", receipt.missingSpend ? "Blocked" : "Not sent", "There is no email or sharing integration in this prototype.")
                if let path = receipt.exportPath { evidence("Export", "Read back", "The exported file matched this sample report at export time.\n\(path)") }
                DisclosureGroup("Read sample report") {
                    Text(receipt.report).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    primary("Export sample Markdown", symbol: "square.and.arrow.up") { library.export(receipt) }
                    Button("Try another case") { ui.page = .skills }.buttonStyle(.bordered)
                }
                Text("Export writes only to the local location you choose. An incomplete report remains labeled as a draft.")
                    .font(.system(size: 12)).foregroundStyle(Color.secondary)
        }
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func badge(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Color.accentColor) }
    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 5) }
            .buttonStyle(.borderedProminent)
    }
    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: symbol).foregroundStyle(Color.secondary); Spacer(); Text(value).font(.system(size: 24, weight: .semibold)) }
            Text(label).font(.system(size: 11)).foregroundStyle(Color.secondary)
        }.padding(18).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private func step(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor).frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(label).font(.system(size: 13, weight: .semibold)); TextField(label, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(label) }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.secondary); Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true) }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
    private func evidence(_ name: String, _ status: String, _ evidence: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(name).font(.system(size: 14, weight: .semibold)); Spacer(); Text(status).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor) }
            Text(evidence).font(.system(size: 12)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
