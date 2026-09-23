import AppKit
import Combine

@MainActor
final class PrototypeStore: ObservableObject {
    @Published var skills: [DemoSkill] = [.sample]
    @Published var receipts: [DemoReceipt] = []
    @Published var notice: String?
    private var canSave = true
    private let file: URL

    private struct Saved: Codable { var skills: [DemoSkill]; var receipts: [DemoReceipt] }

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Understudy/interface-prototype.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
            skills = saved.skills; receipts = saved.receipts
        } catch {
            canSave = false
            notice = "Your saved demo could not be read. It has been left untouched; this session is temporary."
        }
    }

    func save(_ skill: DemoSkill) { skills.append(skill); persist() }

    func rehearse(_ skill: DemoSkill, scenario: DemoScenario) -> DemoReceipt {
        let receipt = DemoEngine.rehearse(skill: skill, scenario: scenario)
        receipts.insert(receipt, at: 0)
        persist()
        return receipt
    }

    func export(_ receipt: DemoReceipt) {
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
            if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
                receipts[index].exportPath = url.path
                persist()
            }
            notice = "Sample exported and read back successfully: \(url.lastPathComponent)"
        } catch { notice = "The sample could not be exported: \(error.localizedDescription)" }
    }

    private func persist() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(skills: skills, receipts: receipts)).write(to: file, options: .atomic)
        } catch { notice = "Your changes work in this session, but could not be saved: \(error.localizedDescription)" }
    }
}
