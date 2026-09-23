import Foundation

/// Connection settings for the Understudy backend (Supabase).
///
/// Looked up in this order:
/// 1. `config.json` inside the app bundle (copied from `app/config.local.json` at build time)
/// 2. `~/Library/Application Support/Understudy/config.json`
///
/// The anon (publishable) key is safe to ship in an app: every table is protected by
/// row-level security, so it only grants what a signed-in user is allowed to see.
/// Secret keys (service role, Anthropic, Google client secret) never go here.
struct AppConfig: Decodable {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static let redirectURL = URL(string: "understudy://auth-callback")!
    static let freeSkillLimit = 5

    static func load() -> AppConfig? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "config", withExtension: "json") { candidates.append(bundled) }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("Understudy/config.json"))
        }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(AppConfig.self, from: data),
                  !config.supabaseAnonKey.isEmpty,
                  !config.supabaseAnonKey.hasPrefix("YOUR_")
            else { continue }
            return config
        }
        return nil
    }
}
