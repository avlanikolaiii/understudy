import Foundation

struct DemoSkill: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var client: String
    var rules: String
    static let sample = DemoSkill(name: "Weekly client update", client: "Norte Studio", rules: "Flag missing figures. Keep the summary concise. Wait for my review before sharing.")
}

enum DemoScenario: String, CaseIterable, Identifiable {
    case complete = "Complete sample"
    case missing = "Missing ad spend"
    var id: String { rawValue }
}

struct DemoReceipt: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var skillName: String
    var client: String
    var missingSpend: Bool
    var report: String
    var rules: String
    var exportPath: String?
    var status: String { missingSpend ? "Needs input" : "Ready for your review" }
}

enum DemoEngine {
    // Deliberately fixed synthetic fixtures. This is not a learned workflow or an AI result.
    static func rehearse(skill: DemoSkill, scenario: DemoScenario) -> DemoReceipt {
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
        return DemoReceipt(skillName: skill.name, client: skill.client, missingSpend: missing, report: report, rules: skill.rules)
    }
}
