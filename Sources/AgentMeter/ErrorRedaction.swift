import Foundation

/// Redacts sensitive details from error strings before they leave the app process.
enum ErrorRedaction {
    nonisolated static func redact(_ message: String) -> String {
        var result = message

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            result = result.replacingOccurrences(of: home, with: "~")
        }

        result = result.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "~",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_-]{8,}"#,
            with: "sk-…",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._~+/=-]+"#,
            with: "Bearer …",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\b(api[_-]?key|key|token|access_token|secret|password)(\s*[=:]\s*)[^\s&,;"']+"#,
            with: "$1$2…",
            options: .regularExpression
        )
        result = redactTokenLikeRuns(in: result)

        return result
    }

    /// Replaces runs of 24+ token characters (including base64's `+`, `/`, `=`)
    /// that mix letters and digits. Plain long words and paths stay readable.
    nonisolated private static func redactTokenLikeRuns(in message: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9._~+/=-]{24,}"#) else {
            return message
        }
        var result = message
        let matches = regex.matches(in: message, range: NSRange(message.startIndex..., in: message))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = result[range]
            if run.contains(where: \.isLetter), run.contains(where: \.isNumber) {
                result.replaceSubrange(range, with: "…")
            }
        }
        return result
    }
}
