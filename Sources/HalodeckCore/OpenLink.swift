import Foundation

/// Which links an "Open link" corner may open: web pages and new mail only. Anything else that
/// `NSWorkspace.open` accepts is refused: a `file:` link would open (and, for a .command file, run)
/// a local file, and a custom scheme would hand the text to whichever app claims it.
public enum OpenLink {
    public static let schemes: Set<String> = ["http", "https", "mailto"]

    /// The link to open for `text` (surrounding whitespace ignored), or nil when it is refused:
    /// another scheme, no scheme, a web link without a host or a mail link without an address.
    public static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else {
            return nil
        }
        if scheme == "mailto" {
            return trimmed.dropFirst(scheme.count + 1).isEmpty ? nil : url
        }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
