import AppKit
import AuthenticationServices
import Foundation
import Supabase

/// Sign-in state. Everything here is real Supabase Auth. Skills and receipts live in `SkillLibrary`.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case notConfigured
        case loading
        case signedOut
        case signedIn(email: String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published var message: String?
    @Published var messageIsError = false
    @Published private(set) var busy = false
    @Published var emailDraft = ""
    @Published var shortcutLabel = "⌥ Space"

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
                } else {
                    self.phase = .signedOut
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

