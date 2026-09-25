import Foundation
import UnderstudyCore

@main
struct CommandChecks {
    static func main() {
        // Spotify links become the URI Spotify plays; anything else is refused.
        precondition(AppCommand.spotifyURI("https://open.spotify.com/album/4a2yy8XJBSmAu4CQHvwxQt?si=abc") == "spotify:album:4a2yy8XJBSmAu4CQHvwxQt")
        precondition(AppCommand.spotifyURI("https://open.spotify.com/intl-es/track/6rqhFgbbKwnb9MLmUQDhG6") == "spotify:track:6rqhFgbbKwnb9MLmUQDhG6")
        precondition(AppCommand.spotifyURI("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M") == "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        precondition(AppCommand.spotifyURI("https://evil.example/album/4a2yy8XJBSmAu4CQHvwxQt") == nil)
        precondition(AppCommand.spotifyURI("spotify:album:x\" & do shell script \"rm") == nil)
        precondition(AppCommand.spotifyURI("spotify:login:abc") == nil)
        print("PASS: Spotify links")

        // Values can't end an AppleScript string or add code.
        precondition(AppCommand.quoted(#"a"b\c"#) == #""a\"b\\c""#)
        guard case .script(let script) = try! AppCommand.musicPlaylist.invocation(["playlist": #"Mix" & do shell script "x"#]) else { fatalError() }
        precondition(script.contains(#"play playlist "Mix\" & do shell script \"x""#) && !script.contains(#"Mix" & do"#))
        guard case .script(let draft) = try! AppCommand.mailDraft.invocation(["to": "a@b.co, c@d.org", "subject": "Hi \"there\"", "body": "Line 1\nLine 2"]) else { fatalError() }
        precondition(draft.contains(#"subject:"Hi \"there\"""#) && draft.contains(#"{address:"c@d.org"}"#) && !draft.contains("send"))
        print("PASS: quoting, no send in drafts")

        // Bad values are refused with a reason; placeholders wait until the run fills them.
        precondition(AppCommand.mailDraft.problem(["to": "not an address"]) != nil)
        precondition(AppCommand.mailDraft.problem(["to": "a@b.co\" & x"]) != nil)
        precondition(AppCommand.browserOpen.problem(["link": "file:///etc/passwd"]) != nil)
        precondition(AppCommand.browserOpen.problem(["link": "https://example.com", "browser": "com.evil.app"]) != nil)
        precondition(AppCommand.browserOpen.problem(["link": "https://example.com", "browser": "com.apple.Safari"]) == nil)
        precondition(AppCommand.finderOpen.problem(["path": "Downloads"]) != nil && AppCommand.finderOpen.problem(["path": "~/Downloads"]) == nil)
        precondition(AppCommand.spotifyPlay.problem(["link": ""]) != nil && AppCommand.spotifyPlay.problem(["link": "{album}"]) == nil)
        precondition(AppCommand.spotifyPause.problem([:]) == nil)
        if case .open(let link, let app) = try! AppCommand.browserOpen.invocation(["link": "https://example.com", "browser": ""]) {
            precondition(link == "https://example.com" && app == nil)
        } else { fatalError() }
        print("PASS: values checked")

        // Steps carry only their fields; values fill command fields too.
        let step = AppCommand.spotifyPlay.step(["link": "{album}", "extra": "x"])
        precondition(step.parameters["action"] == "command" && step.parameters["command"] == "spotifyPlay" && step.parameters["extra"] == nil)
        precondition(step.target.app == AppCommand.spotify && step.executor == .appleScript && !step.effect.needsApproval)
        precondition(Variables.names(in: [step]) == ["album"])
        precondition(Variables.fill(step, with: ["album": "spotify:album:abc"]).parameters["link"] == "spotify:album:abc")
        precondition(AppCommand.mailDraft.step(["to": "a@b.co"]).effect == .write)
        print("PASS: steps and values")

        // Reports: playing, paused, a draft.
        precondition(AppCommand.spotifyPlay.verified("Playing: Bloom — Caligula's Horse") && !AppCommand.spotifyPlay.verified("Not playing (paused)"))
        precondition(AppCommand.spotifyPause.verified("Not playing (paused)") && AppCommand.mailDraft.verified("Draft to a@b.co is open in Mail, not sent."))
        print("PASS: reports")

        // Spotify's clicks (and opening Spotify for them) become one command; other steps stay in order.
        typealias Step = SkillDefinition.Step
        let open = Step(id: "1", intent: "Open Spotify", executor: .appleScript, target: .init(app: AppCommand.spotify), effect: .read,
                        evidence: .readBack, parameters: ["action": "activate", "app": "Spotify"])
        let album = Step(id: "2", intent: "Press Bloom", executor: .accessibility, target: .init(app: AppCommand.spotify, role: "AXButton", title: "Bloom"),
                         effect: .write, evidence: .none, parameters: ["action": "press"])
        let play = Step(id: "3", intent: "Press Play", executor: .accessibility, target: .init(app: AppCommand.spotify, role: "AXButton", title: "Play"),
                        effect: .write, evidence: .none, parameters: ["action": "press"])
        let wait = ManualStep.waitSeconds(2)
        let replaced = AppCommand.replacingSpotifyClicks(in: [wait, open, album, play], with: "spotify:track:abc", name: "Bloom — Caligula's Horse")!
        precondition(replaced.count == 2 && replaced[0] == wait && replaced[1].parameters["command"] == "spotifyPlay"
                     && replaced[1].parameters["link"] == "spotify:track:abc" && replaced[1].intent.contains("Bloom"))
        precondition(AppCommand.replacingSpotifyClicks(in: [wait, open], with: "spotify:track:abc", name: "x") == nil)
        print("PASS: Spotify's own command instead of clicks")
    }
}
