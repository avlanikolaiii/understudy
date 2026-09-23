import Combine
import Foundation

enum PrototypePage: String, CaseIterable {
    case home = "Home", teach = "Teach a skill", skills = "My skills", results = "Run results"
    var symbol: String {
        switch self { case .home: "square.grid.2x2"; case .teach: "plus.circle"; case .skills: "square.stack.3d.up"; case .results: "checkmark.rectangle" }
    }
}

/// Window navigation and draft state stay alive when the workspace is closed.
@MainActor
final class WorkspaceState: ObservableObject {
    @Published var page: PrototypePage? = .home
    @Published var teachingStep = 0
    @Published var skillName = "Weekly client update"
    @Published var clientName = "Norte Studio"
    @Published var rules = DemoSkill.sample.rules
    @Published var selectedSkill: DemoSkill?
    @Published var scenario: DemoScenario = .complete
    @Published var selectedReceipt: UUID?

    func showTeaching(watch: WatchSession) {
        page = .teach
        if watch.isPresented { teachingStep = 1 }
    }

    func startWatch(_ watch: WatchSession) {
        page = .teach
        teachingStep = 1
        if !watch.isPresented { watch.start() }
    }

    func reviewWatch(_ watch: WatchSession) {
        watch.stop()
        watch.addRule()
        // Copy demo notes once even when the user goes back and reviews again.
        var notes = rules.components(separatedBy: .newlines)
        for rule in watch.rules where !notes.contains(rule) { notes.append(rule) }
        rules = notes.filter { !$0.isEmpty }.joined(separator: "\n")
        teachingStep = 2
        page = .teach
    }
}
