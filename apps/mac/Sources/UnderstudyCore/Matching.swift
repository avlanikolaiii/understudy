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
}
