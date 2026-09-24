import Foundation
import Supabase
import UnderstudyCore

/// The signed-in person's account: the source of truth for their skills and receipts, in Supabase
/// behind row-level security (see supabase/migrations). Each call reads or writes the server directly.
struct AccountStore {
    let client: SupabaseClient

    /// The plan name, or nil if it couldn't be read.
    func plan() async -> String? {
        let profile: ProfileRow? = try? await client.from("profiles").select("plan").single().execute().value
        return profile?.plan
    }

    /// The skills, oldest first. On first sign-in the sample skill is added so the account isn't empty.
    func skills() async throws -> [Skill] {
        var rows: [SkillRow] = try await client.from("skills").select(SkillRow.columns).order("created_at").execute().value
        if rows.isEmpty {
            try await client.from("skills").insert(NewSkillRow(.sample)).execute()
            rows = try await client.from("skills").select(SkillRow.columns).order("created_at").execute().value
        }
        return rows.map(\.skill)
    }

    /// The newest receipts first.
    func receipts(limit: Int = 50) async throws -> [Receipt] {
        let rows: [ReceiptRow] = try await client.from("receipts").select(ReceiptRow.columns)
            .order("created_at", ascending: false).limit(limit).execute().value
        return rows.map(\.receipt)
    }

    /// Saves a new skill and returns it as stored, with the server's id.
    func save(_ skill: Skill) async throws -> Skill {
        let row: SkillRow = try await client.from("skills").insert(NewSkillRow(skill))
            .select(SkillRow.columns).single().execute().value
        return row.skill
    }

    /// Replaces a saved skill's definition (its steps, notes, and recording link).
    func update(_ skill: Skill) async throws -> Skill {
        let row: SkillRow = try await client.from("skills").update(DefinitionRow(definition: skill.definition))
            .eq("id", value: skill.id).select(SkillRow.columns).single().execute().value
        return row.skill
    }

    func save(_ receipt: Receipt, skill: Skill) async throws {
        try await client.from("receipts").insert(NewReceiptRow(receipt, skill: skill)).execute()
    }
}

// MARK: Rows

private struct SkillRow: Decodable {
    static let columns = "id,name,client,is_sample,definition"
    let id: UUID
    let name: String
    let client: String?
    let is_sample: Bool
    let definition: SkillDefinition?

    var skill: Skill {
        Skill(id: id, name: name, client: client ?? "",
              definition: definition ?? (is_sample ? Skill.sample.definition : .prepared(notes: "")), isSample: is_sample)
    }
}

private struct NewSkillRow: Encodable {
    let name: String
    let client: String
    let is_sample: Bool
    let definition: SkillDefinition
    init(_ skill: Skill) {
        name = skill.name; client = skill.client; is_sample = skill.isSample; definition = skill.definition
    }
}

private struct DefinitionRow: Encodable {
    let definition: SkillDefinition
}

private struct ProfileRow: Decodable {
    let plan: String
}

private struct ReceiptRow: Decodable {
    static let columns = "id,created_at,kind,ready_to_send,steps,skill_name,client,report"
    let id: UUID
    let created_at: Date
    let kind: String
    let ready_to_send: Bool
    let steps: [ReceiptStep]?
    let skill_name: String?
    let client: String?
    let report: String?

    var receipt: Receipt {
        let run = kind == "run"
        return Receipt(id: id, date: created_at, skillName: skill_name ?? "Skill", client: client ?? "",
                       missingSpend: !run && !ready_to_send, report: report ?? "", rules: "",
                       ranSteps: run ? steps ?? [] : nil, outcome: run ? (ready_to_send ? "Completed" : "Blocked · needs you") : nil)
    }
}

private struct NewReceiptRow: Encodable {
    let id: UUID
    let skill_id: UUID
    let kind: String
    let ready_to_send: Bool
    let steps: [ReceiptStep]
    let skill_name: String
    let client: String
    let report: String
    let simulated: Bool
    init(_ receipt: Receipt, skill: Skill) {
        id = receipt.id; skill_id = skill.id; ready_to_send = receipt.readyToSend; steps = receipt.steps
        kind = receipt.isRun ? "run" : "rehearsal"; simulated = !receipt.isRun
        skill_name = receipt.skillName; client = receipt.client; report = receipt.report
    }
}
