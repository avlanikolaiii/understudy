import Foundation

/// One skill type for the whole app, in sample mode (saved on this Mac) and in an account (Supabase).
/// Skills are prepared from the simulated Watch replay. They are not learned by AI.
struct Skill: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var client: String
    var rules: String
    /// The seeded example skill. Taught (simulated) skills are `false`.
    var isSample = false

    static let sample = Skill(name: "Weekly client update", client: "Norte Studio",
                              rules: "Flag missing figures. Keep the summary concise. Wait for my review before sharing.",
                              isSample: true)

    init(id: UUID = UUID(), name: String, client: String, rules: String, isSample: Bool = false) {
        self.id = id; self.name = name; self.client = client; self.rules = rules; self.isSample = isSample
    }

    // Files saved by the earlier interface prototype have no `isSample` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        client = try c.decode(String.self, forKey: .client)
        rules = try c.decode(String.self, forKey: .rules)
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? (name == Skill.sample.name && client == Skill.sample.client)
    }
}

enum SampleCase: String, CaseIterable, Identifiable {
    case complete = "Complete sample"
    case missing = "Missing ad spend"
    var id: String { rawValue }
}

/// A rehearsal receipt. Status (what happened) and evidence (how it was checked) stay separate.
struct Receipt: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var skillName: String
    var client: String
    var missingSpend: Bool
    var report: String
    var rules: String
    var exportPath: String?

    var status: String { missingSpend ? "Needs input" : "Ready for your review" }
    var readyToSend: Bool { !missingSpend }

    /// One line per step, used by the notch strip and stored in `receipts.steps`.
    var steps: [ReceiptStep] {
        missingSpend ? [
            ReceiptStep(step: "Ad spend", status: "Blocked · needs you", evidence: "Not verifiable: the sample figure is missing, so it wasn't guessed."),
            ReceiptStep(step: "Report", status: "Partly done · incomplete draft", evidence: "Sample only: spend and cost per lead read “[missing: …]”."),
            ReceiptStep(step: "Tracker", status: "Needs input", evidence: "Not connected in this prototype."),
            ReceiptStep(step: "Email", status: "Held back", evidence: "Not drafted while the report is incomplete."),
        ] : [
            ReceiptStep(step: "Figures", status: "Done", evidence: "Sample only: fixed fictional inputs, no source was queried."),
            ReceiptStep(step: "Report", status: "Done · ready for review", evidence: "Created locally from the sample template."),
            ReceiptStep(step: "Tracker", status: "Not connected", evidence: "No tracker is connected in this prototype."),
            ReceiptStep(step: "Email", status: "Not sent", evidence: "No email integration in this prototype."),
        ]
    }
}

struct ReceiptStep: Codable, Equatable {
    let step: String
    let status: String
    let evidence: String
}

enum SampleEngine {
    // Deliberately fixed synthetic fixtures. This is not a learned workflow or an AI result.
    static func rehearse(skill: Skill, scenario: SampleCase) -> Receipt {
        let missing = scenario == .missing
        let report = """
        # \(skill.client) · Weekly client update\(missing ? " (DRAFT, incomplete)" : "")

        SAMPLE OUTPUT · Interface prototype · Synthetic data

        ## Numbers
        Impressions: 100,000
        Clicks: 2,500
        Click-through rate: 2.50%
        Leads: 125
        Ad spend: \(missing ? "[missing: needs input]" : "$1,250.00")
        Cost per lead: \(missing ? "[missing: depends on ad spend]" : "$10.00")

        ## Summary
        The sample campaign generated 125 leads from 2,500 clicks.
        \(missing ? "Video ad spend is missing. Total spend and cost per lead cannot be reported." : "Sample cost per lead was $10.00. No previous-week data is provided for comparison.")

        ## Next step
        \(missing ? "Provide the missing Video spend, then rehearse again. This draft is not ready to share." : "Review the report before sharing. Nothing has been sent or changed in another app.")

        ## Your workflow notes
        \(skill.rules)

        Notes are saved with this sample skill. AI interpretation and enforcement are not connected.
        """
        return Receipt(skillName: skill.name, client: skill.client, missingSpend: missing, report: report, rules: skill.rules)
    }
}

/// Sample mode storage: a JSON file on this Mac. A file that can't be read is never overwritten.
struct LocalLibraryFile {
    struct Contents: Codable {
        var skills: [Skill]
        var receipts: [Receipt]
    }

    let url: URL

    static var standard: LocalLibraryFile {
        LocalLibraryFile(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Understudy/interface-prototype.json"))
    }

    /// `nil` means there is no file yet. A throw means the file exists but can't be read.
    func load() throws -> Contents? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url))
    }

    func save(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: url, options: .atomic)
    }
}
