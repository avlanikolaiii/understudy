import SwiftUI

/// The one main window: teaching, skills, receipts, and the account. The notch is its live companion.
struct MainWindowView: View {
    @ObservedObject var auth: AppModel
    @ObservedObject var library: SkillLibrary
    @ObservedObject var ui: WorkspaceState
    @ObservedObject var watch: WatchSession
    @ObservedObject var activity: NotchActivity
    var openSettings: () -> Void = {}

    private var activeSkill: Skill {
        library.skills.first(where: { $0.id == ui.selectedSkill?.id }) ?? library.skills.first ?? .sample
    }
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
                }.help("Start or resume the simulated teaching flow")
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }.help("Change keyboard shortcut")
            }
        }
        .onReceive(watch.$phase) { phase in
            if phase == .playing { ui.page = .teach; ui.teachingStep = 1 }
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("Make room for your real work.", "Teach a routine. Review what it learned. See the result.")
            VStack(alignment: .leading, spacing: 18) {
                HStack { badge("START HERE"); Spacer(); Image(systemName: "sparkles").foregroundStyle(Color.accentColor) }
                Text("Show it once. Then hand it off.").font(.title.weight(.semibold))
                Text("Walk through a weekly client report with fictional campaign data. Nothing is recorded, connected, or sent.")
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
            step("1", "Show your process", "Explore a sample demonstration and save your workflow notes.")
            step("2", "Try a different case", "Switch between complete inputs and a missing figure.")
            step("3", "See what happened", "Read the sample report, its status, and the limits of its evidence.")
        }
    }

    private var teach: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Teach a skill", "Start Watch here or from the notch. This prototype replays a predefined example.")
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
                Text("These notes are stored locally. The prototype does not interpret or enforce custom rules.")
                    .font(.system(size: 12)).foregroundStyle(Color.secondary)
                primary(watch.isPresented ? "Resume Watch demo" : "Start Watch demo", symbol: "record.circle") { ui.startWatch(watch) }
                    .disabled(ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if ui.teachingStep == 1 {
                WorkspaceWatchView(session: watch, onReview: { ui.reviewWatch(watch) })
                Button("Back to description") { ui.teachingStep = 0 }
            } else {
                badge("SAMPLE SKILL · NOT AI-GENERATED")
                field("Skill name", text: $ui.skillName)
                field("Client or project", text: $ui.clientName)
                detail("PROCEDURE", "Read sample figures → fill the report → flag missing data → wait for review")
                detail("YOUR NOTES", ui.rules.isEmpty ? "No additional notes." : ui.rules)
                HStack {
                    Button("Back") { ui.teachingStep = 1 }
                    primary("Save sample skill", symbol: "checkmark") {
                        let skill = Skill(name: ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines), client: ui.clientName.trimmingCharacters(in: .whitespacesAndNewlines), rules: ui.rules)
                        library.save(skill) { saved in ui.selectedSkill = saved; activity.showLearned(saved) }
                        watch.dismiss(); ui.teachingStep = 0; ui.page = .skills
                    }
                    .disabled(ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                        Spacer(); Text(skill.isSample ? "Sample" : "Simulated").font(.caption).foregroundStyle(.secondary)
                        if activeSkill.id == skill.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(activeSkill.id == skill.id ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor)))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider()
            Text("Rehearse \(activeSkill.name)").font(.system(size: 20, weight: .semibold))
            Text("Watch it rehearse in the notch. It uses fixed sample inputs, doesn't test AI learning, and doesn't connect to your accounts.")
                .font(.system(size: 13)).foregroundStyle(Color.secondary)
            Picker("Sample inputs", selection: $ui.scenario) {
                ForEach(SampleCase.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            detail("WHAT CHANGES", ui.scenario == .complete ? "All sample figures are present. The report is ready for your review." : "Video spend is absent. Total spend and cost per lead stay missing; sharing is blocked.")
            HStack(spacing: 12) {
                primary("Rehearse sample", symbol: "play.fill") {
                    let skill = activeSkill
                    activity.rehearse(skill, scenario: ui.scenario, record: { library.record($0, skill: skill) }) { receipt in
                        ui.selectedReceipt = receipt.id; ui.page = .results
                    }
                }.disabled(activity.isRehearsing)
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
                        ForEach(library.receipts) { item in Text("\(item.client) · \(item.status) · \(item.date.formatted(date: .omitted, time: .standard))").tag(item.id) }
                    }
                }
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
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.rectangle").font(.system(size: 40)).foregroundStyle(Color.secondary)
                    Text("Your first receipt starts with a rehearsal.").font(.system(size: 18, weight: .medium))
                    primary("Explore a sample skill", symbol: "arrow.right") { ui.page = .skills }
                }.frame(maxWidth: .infinity).padding(.vertical, 70)
            }
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
