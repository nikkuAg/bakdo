import Foundation

/// Cleans raw Whisper output before it is typed into the focused app.
enum TextPostProcessor {
    struct Options {
        var removeFillers = true
        var spokenCommands = true
        var replacements: [Replacement] = []
    }

    /// Whole outputs Whisper is known to invent from silence or noise.
    private static let hallucinations: [String] = [
        "thank you for watching", "thanks for watching", "please subscribe", "subscribe to my channel",
        "subtitles by", "amara.org", "transcribed by", "the end", "you", "bye", "bye bye",
        "dhanyavaad", "dhanyawad", "धन्यवाद", "शुक्रिया", "like and subscribe",
    ]

    static func process(_ raw: String, options: Options) -> String {
        var text = raw

        // Non-speech annotations: [BLANK_AUDIO], (music), *laughs*, ♪
        text = text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*(music|laugh|cough|applause|noise|silence|inaudible|sigh)[^)]*\)|\*[^*]+\*|♪+"#,
                                         with: " ", options: [.regularExpression, .caseInsensitive])
        text = collapseWhitespace(text)

        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if normalized.isEmpty || hallucinations.contains(normalized) { return "" }

        if options.removeFillers {
            // "Um, so I think" -> "so I think". Hindi hesitation sounds included.
            let fillers = #"(?<![\p{L}\p{N}'])(u+m+|u+h+|e+r+m+|h+m+|m+h+m+|a+h+|उम्म*|अं+|हम्म*)(?![\p{L}\p{N}'])[,.…]*\s*"#
            text = text.replacingOccurrences(of: fillers, with: "", options: [.regularExpression, .caseInsensitive])
            // Immediate word repetitions from stutters: "the the" -> "the"
            text = text.replacingOccurrences(of: #"\b(\p{L}+)(\s+\1\b)+"#, with: "$1", options: [.regularExpression, .caseInsensitive])
            text = collapseWhitespace(text)
        }

        if options.spokenCommands {
            text = text.replacingOccurrences(of: #"[,.]?\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: #"[,.]?\s*\bnew line\b[,.]?\s*"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        }

        for replacement in options.replacements where !replacement.from.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: replacement.from.trimmingCharacters(in: .whitespaces)) + #"(?![\p{L}\p{N}])"#
            text = text.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: replacement.to),
                                             options: [.regularExpression, .caseInsensitive])
        }

        text = text.trimmingCharacters(in: .whitespaces)
        // Fix stray space before punctuation and capitalise the first letter.
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        if let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
