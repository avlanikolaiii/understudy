import AppKit
import AuthenticationServices
import Foundation
import Supabase

/// A skill as stored in the `skills` table (see supabase/migrations).
struct SkillRow: Decodable, Identifiable {
    let id: UUID
    let name: String
    let client: String?
    let isSample: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, client
        case isSample = "is_sample"
    }
}

private struct NewSkill: Encodable {
    let name: String
    let client: String
    let is_sample: Bool
}

private struct ProfileRow: Decodable {
    let plan: String
}

/// Sign-in state and the signed-in user's data. Everything here is real:
/// Supabase Auth for sign-in, and the database (behind row-level security) for skills.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case notConfigured
        case loading
        case signedOut
        case signedIn(email: String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var skills: [SkillRow] = []
    @Published private(set) var plan = "free"
    @Published var message: String?
    @Published var messageIsError = false
    @Published private(set) var busy = false
    @Published var emailDraft = ""

    @Published var shortcutLabel = "⌥ Space"
    var openSettings: (() -> Void)?

    var openWorkspace: (() -> Void)?

    let client: SupabaseClient?

    init() {
        if let config = AppConfig.load() {
            client = SupabaseClient(
                supabaseURL: config.supabaseURL,
                supabaseKey: config.supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: .init(redirectToURL: AppConfig.redirectURL, flowType: .pkce, emitLocalSessionAsInitialSession: true)
                )
            )
        } else {
            client = nil
            phase = .notConfigured
        }
    }

    func start() {
        guard let client else { return }
        Task { [weak self] in
            for await (_, session) in client.auth.authStateChanges {
                guard let self else { return }
                if let session, !session.isExpired {
                    self.phase = .signedIn(email: session.user.email ?? "your account")
                    await self.loadAccount()
                } else {
                    self.phase = .signedOut
                    self.skills = []
                }
            }
        }
    }

    // MARK: Sign-in

    func signIn(with provider: Provider) {
        guard let client else { return }
        run("Opening sign-in…") {
            try await client.auth.signInWithOAuth(provider: provider, redirectTo: AppConfig.redirectURL)
            self.say(nil)
        }
    }

    func sendEmailLink(to email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil else {
            say("Enter an email address like you@agency.com.", error: true)
            return
        }
        guard let client else { return }
        run("Sending your sign-in link…") {
            try await client.auth.signInWithOTP(email: trimmed, redirectTo: AppConfig.redirectURL)
            self.say("Check \(trimmed) for a sign-in link. Open it on this Mac.")
        }
    }

    /// Called when the email link (or an OAuth redirect) opens `understudy://auth-callback`.
    func handle(url: URL) {
        guard let client, url.scheme == AppConfig.redirectURL.scheme else { return }
        run("Signing you in…") {
            _ = try await client.auth.session(from: url)
            self.say(nil)
        }
    }

    func signOut() {
        guard let client else { return }
        run("Signing out…") {
            try await client.auth.signOut()
            self.say(nil)
        }
    }

    // MARK: Account data

    var skillCountText: String {
        let owned = skills.filter { !$0.isSample }.count   // the sample skill doesn't count toward the limit
        return plan == "free" ? "\(owned) of \(AppConfig.freeSkillLimit) skills used" : "\(owned) skills"
    }

    private func loadAccount() async {
        guard let client else { return }
        do {
            if let profile: ProfileRow = try? await client.from("profiles").select("plan").single().execute().value {
                plan = profile.plan
            }
            var rows: [SkillRow] = try await client.from("skills").select("id,name,client,is_sample").order("created_at").execute().value
            if rows.isEmpty {
                // First sign-in: add the sample skill so the account isn't empty. It's marked as a sample.
                try await client.from("skills").insert(NewSkill(name: "Weekly client update", client: "Norte Studio", is_sample: true)).execute()
                rows = try await client.from("skills").select("id,name,client,is_sample").order("created_at").execute().value
            }
            skills = rows
        } catch {
            say("Signed in, but your skills couldn't load: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Helpers

    private func run(_ status: String, _ work: @escaping () async throws -> Void) {
        busy = true
        say(status)
        Task {
            do { try await work() }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                say(nil)
            } catch {
                say(Self.describe(error), error: true)
            }
            busy = false
        }
    }

    private func say(_ text: String?, error: Bool = false) {
        message = text
        messageIsError = error
    }

    private static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("provider is not enabled") || text.localizedCaseInsensitiveContains("unsupported provider") {
            return "That sign-in option isn't turned on in Supabase yet. See docs/setup/accounts.md."
        }
        if text.localizedCaseInsensitiveContains("offline") || text.localizedCaseInsensitiveContains("network") {
            return "Can't reach the Understudy server. Check your connection and try again."
        }
        return text
    }
}

