import AppKit
import Combine
import Foundation
import Supabase

/// The app's one list of skills and receipts. Before sign-in it's sample mode, saved on
/// this Mac. After sign-in it's the user's account (Supabase, behind row-level security).
@MainActor
final class SkillLibrary: ObservableObject {
    enum Mode: Equatable {
        case sample
        case account(email: String)
    }

    @Published private(set) var mode: Mode = .sample
    @Published private(set) var skills: [Skill] = [.sample]
    @Published private(set) var receipts: [Receipt] = []
    @Published private(set) var plan = "free"
    @Published private(set) var loading = false
    @Published var notice: String?

    private let auth: AppModel
    private let file: LocalLibraryFile
    private var local = LocalLibraryFile.Contents(skills: [.sample], receipts: [])
    private var canSaveLocal = true
    private var bag = Set<AnyCancellable>()
    /// Changes on every sign-in or sign-out. Async work started under an older owner is dropped.
    private var owner = 0

    init(auth: AppModel, file: LocalLibraryFile = .standard) {
        self.auth = auth
        self.file = file
        do {
            if let saved = try file.load() { local = saved }
        } catch {
            canSaveLocal = false
            notice = "Your saved sample skills couldn't be read. The file was left untouched; changes this session are temporary."
        }
        showLocal()
        auth.$phase.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.authChanged(phase) }
            .store(in: &bag)
    }

    var modeText: String {
        switch mode {
        case .sample: "Sample mode · saved on this Mac"
        case .account(let email): email
        }
    }

    /// In an account, rehearsals need a skill that's really saved there.
    var canRehearse: Bool { mode == .sample || (!loading && !skills.isEmpty) }

    var skillCountText: String {
        let owned = skills.filter { !$0.isSample }.count   // the sample skill doesn't count toward the limit
        return plan == "free" ? "\(owned) of \(AppConfig.freeSkillLimit) skills used" : "\(owned) skills"
    }

    // MARK: Changes

    func save(_ skill: Skill, done: @escaping (Skill) -> Void = { _ in }) {
        switch mode {
        case .sample:
            local.skills.append(skill)
            persistLocal()
            showLocal()
            done(skill)
        case .account:
            guard let client = auth.client else { return }
            let started = owner
            Task {
                do {
                    let row: SkillRow = try await client.from("skills")
                        .insert(NewSkillRow(skill))
                        .select(SkillRow.columns).single().execute().value
                    guard started == owner else { return }
                    let saved = row.skill
                    skills.append(saved)
                    done(saved)
                } catch {
                    guard started == owner else { return }
                    notice = "The skill wasn't saved to your account: \(Self.describe(error))"
                }
            }
        }
    }

    /// Returns a recorder bound to whoever is signed in now. If the user signs in or out
    /// before the rehearsal finishes, its receipt is shown but not saved anywhere.
    func recorder(for skill: Skill) -> (Receipt) -> Receipt {
        let started = owner
        return { [weak self] receipt in
            guard let self else { return receipt }
            guard started == self.owner else {
                self.notice = "You signed in or out during the rehearsal, so its receipt wasn't saved."
                return receipt
            }
            return self.record(receipt, skill: skill)
        }
    }

    /// Records a finished (simulated) rehearsal and returns its receipt.
    @discardableResult
    func record(_ receipt: Receipt, skill: Skill) -> Receipt {
        receipts.insert(receipt, at: 0)
        switch mode {
        case .sample:
            local.receipts.insert(receipt, at: 0)
            persistLocal()
        case .account:
            guard let client = auth.client else { break }
            Task {
                do {
                    try await client.from("receipts").insert(NewReceiptRow(receipt, skill: skill)).execute()
                } catch {
                    notice = "This receipt is shown here but wasn't saved to your account: \(Self.describe(error))"
                }
            }
        }
        return receipt
    }

    func export(_ receipt: Receipt) {
        let panel = NSSavePanel()
        panel.title = "Export sample report"
        panel.nameFieldStringValue = "Understudy-sample-\(receipt.missingSpend ? "incomplete" : "report").md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try receipt.report.write(to: url, atomically: true, encoding: .utf8)
            guard try String(contentsOf: url, encoding: .utf8) == receipt.report else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let index = receipts.firstIndex(where: { $0.id == receipt.id }) { receipts[index].exportPath = url.path }
            if mode == .sample, let index = local.receipts.firstIndex(where: { $0.id == receipt.id }) {
                local.receipts[index].exportPath = url.path
                persistLocal()
            }
            notice = "Sample exported and read back successfully: \(url.lastPathComponent)"
        } catch {
            notice = "The sample could not be exported: \(error.localizedDescription)"
        }
    }

    // MARK: Switching between sample mode and the account

    private func authChanged(_ phase: AppModel.Phase) {
        let newMode: Mode
        if case .signedIn(let email) = phase { newMode = .account(email: email) } else { newMode = .sample }
        guard newMode != mode else { return }
        owner += 1
        if case .signedIn(let email) = phase {
            mode = .account(email: email)
            skills = []; receipts = []
            Task { await loadAccount() }
        } else {
            mode = .sample
            plan = "free"
            showLocal()
        }
    }

    private func showLocal() {
        skills = local.skills.isEmpty ? [.sample] : local.skills
        receipts = local.receipts
    }

    private func persistLocal() {
        guard canSaveLocal else { return }
        do { try file.save(local) }
        catch { notice = "Your changes work in this session, but couldn't be saved: \(error.localizedDescription)" }
    }

    private func loadAccount() async {
        guard let client = auth.client else { return }
        let started = owner
        loading = true
        defer { if started == owner { loading = false } }
        do {
            let profile: ProfileRow? = try? await client.from("profiles").select("plan").single().execute().value
            guard started == owner else { return }
            if let profile { plan = profile.plan }
            var rows: [SkillRow] = try await client.from("skills").select(SkillRow.columns).order("created_at").execute().value
            if rows.isEmpty {
                // First sign-in: add the sample skill so the account isn't empty. It's marked as a sample.
                try await client.from("skills").insert(NewSkillRow(.sample)).execute()
                rows = try await client.from("skills").select(SkillRow.columns).order("created_at").execute().value
            }
            let receiptRows: [ReceiptRow] = try await client.from("receipts").select(ReceiptRow.columns)
                .order("created_at", ascending: false).limit(50).execute().value
            // Signed out or switched accounts while loading: drop the old owner's data.
            guard started == owner else { return }
            skills = rows.map(\.skill)
            receipts = receiptRows.map(\.receipt)
        } catch {
            guard started == owner else { return }
            notice = "Signed in, but your skills couldn't load: \(Self.describe(error))"
        }
    }

    private static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("offline") || text.localizedCaseInsensitiveContains("network") {
            return "can't reach the Understudy server. Check your connection and try again."
        }
        return text
    }
}

// MARK: Database rows (see supabase/migrations)

private struct SkillDefinition: Codable {
    var rules: String
    var simulated = true
}

private struct SkillRow: Decodable {
    static let columns = "id,name,client,is_sample,definition"
    let id: UUID
    let name: String
    let client: String?
    let is_sample: Bool
    let definition: SkillDefinition?

    var skill: Skill {
        Skill(id: id, name: name, client: client ?? "", rules: definition?.rules ?? (is_sample ? Skill.sample.rules : ""), isSample: is_sample)
    }
}

private struct NewSkillRow: Encodable {
    let name: String
    let client: String
    let is_sample: Bool
    let definition: SkillDefinition
    init(_ skill: Skill) {
        name = skill.name; client = skill.client; is_sample = skill.isSample
        definition = SkillDefinition(rules: skill.rules)
    }
}

private struct ProfileRow: Decodable {
    let plan: String
}

private struct ReceiptRow: Decodable {
    static let columns = "id,created_at,ready_to_send,skill_name,client,report"
    let id: UUID
    let created_at: Date
    let ready_to_send: Bool
    let skill_name: String?
    let client: String?
    let report: String?

    var receipt: Receipt {
        Receipt(id: id, date: created_at, skillName: skill_name ?? "Skill", client: client ?? "",
                missingSpend: !ready_to_send, report: report ?? "", rules: "")
    }
}

private struct NewReceiptRow: Encodable {
    let id: UUID
    let skill_id: UUID
    let kind = "rehearsal"
    let ready_to_send: Bool
    let steps: [ReceiptStep]
    let skill_name: String
    let client: String
    let report: String
    let simulated = true
    init(_ receipt: Receipt, skill: Skill) {
        id = receipt.id; skill_id = skill.id; ready_to_send = receipt.readyToSend; steps = receipt.steps
        skill_name = receipt.skillName; client = receipt.client; report = receipt.report
    }
}
