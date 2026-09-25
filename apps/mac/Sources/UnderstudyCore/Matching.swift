import Foundation

/// How a run finds an element that changed a little, and how it recognizes that a step worked.
/// Pure rules, so they're checked without any app.
public enum Matching {
    /// The words that identify a name: its first part, before " · " or " • ".
    /// "Bloom Album • Caligula's Horse" → "Bloom Album"; "Bloom · Recents" → "Bloom".
    public static func keyword(_ name: String) -> String {
        let first = name.components(separatedBy: " · ").first ?? name
        return (first.components(separatedBy: " • ").first ?? first).trimmingCharacters(in: .whitespaces)
    }

    /// A name that's clearly the same thing, changed a little: one keyword is the other plus more
    /// words (at least 3 letters, whole words only), ignoring case. "Bloom" ~ "Bloom (Deluxe)",
    /// but not "Play" ~ "Playlist".
    public static func similar(_ recorded: String, _ candidate: String) -> Bool {
        let a = keyword(recorded).lowercased(), b = keyword(candidate).lowercased()
        guard a.count >= 3, b.count >= 3, a != b else { return false }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        guard long.hasPrefix(short) else { return false }
        return !(long.dropFirst(short.count).first?.isLetter ?? false) && !(long.dropFirst(short.count).first?.isNumber ?? false)
    }

    /// Whether pressing something named `name` visibly led somewhere: its keyword now appears in
    /// the window title or a heading more often than before. "Bloom" pressed → a "Bloom" heading.
    public static func appeared(after name: String, before: [String], after texts: [String]) -> Bool {
        let key = keyword(name).lowercased()
        guard key.count >= 3 else { return false }
        // A heading may be just the start of the name ("Bloom" for "Bloom Album").
        func matches(_ text: String) -> Bool {
            let t = text.lowercased()
            return t.contains(key) || (t.count >= 4 && key.hasPrefix(t))
        }
        func count(_ list: [String]) -> Int { list.filter(matches).count }
        return count(texts) > count(before)
    }

    // MARK: Quick launcher

    /// How well what's typed in the quick launcher fits a skill's name, higher is better, or nil
    /// when it doesn't fit: the name starts with it (300), a word starts with it (200), it's
    /// inside the name (100), or its letters appear in order, like "pb" for "Play Bloom" (50).
    /// Case and accents are ignored. Empty text fits everything equally.
    public static func launcherScore(_ typed: String, _ name: String) -> Int? {
        let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let query = fold(typed.trimmingCharacters(in: .whitespaces)), target = fold(name)
        guard !query.isEmpty else { return 1 }
        if target.hasPrefix(query) { return 300 }
        let words = target.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { $0.hasPrefix(query) }) { return 200 }
        if target.contains(query) { return 100 }
        var rest = Substring(target)
        for character in query where !character.isWhitespace {
            guard let found = rest.firstIndex(of: character) else { return nil }
            rest = rest[rest.index(after: found)...]
        }
        return 50
    }

    /// Names ranked for what's typed: best fit first, then alphabetically. Names that don't fit are left out.
    public static func launcherRanked(_ typed: String, _ names: [String]) -> [Int] {
        names.indices.compactMap { index in launcherScore(typed, names[index]).map { (index, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : names[$0.0].localizedCaseInsensitiveCompare(names[$1.0]) == .orderedAscending }
            .map(\.0)
    }
}
