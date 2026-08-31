import Foundation

/// Renders the Markdown of a text slide to a self-contained HTML page.
///
/// Deliberately small: a presentation slide wants headings, emphasis and
/// bullets, not a full CommonMark implementation. Everything is escaped before
/// any markup is inserted, so slide text can contain `<`, `&` or quotes safely.
enum MarkdownSlide {

    static func html(for markdown: String, textAlignment: String = "center") -> String {
        let body = blocks(from: markdown)
            .map(render)
            .joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{width:100%;height:100%}
        body{
          background:#000;color:#fff;
          display:flex;align-items:center;justify-content:center;
          font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
          font-size:clamp(1rem,3.2vmin,3rem);line-height:1.45;
          -webkit-font-smoothing:antialiased;
        }
        .slide{max-width:min(1100px,88vw);padding:4vmin;text-align:\(textAlignment)}
        h1{font-size:2.1em;line-height:1.15;margin:0 0 .45em;font-weight:700;letter-spacing:-0.02em}
        h2{font-size:1.6em;line-height:1.2;margin:0 0 .4em;font-weight:650}
        h3{font-size:1.25em;margin:0 0 .35em;font-weight:600}
        p{margin:0 0 .7em}
        ul{margin:0 0 .7em;padding-left:1.4em;text-align:left;display:inline-block}
        li{margin:0 0 .35em}
        strong{font-weight:700}
        em{font-style:italic}
        code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85em;
             background:rgba(255,255,255,.12);padding:.12em .35em;border-radius:.25em}
        hr{border:0;border-top:2px solid rgba(255,255,255,.25);margin:1em 0}
        :is(h1,h2,h3,p,ul):last-child{margin-bottom:0}
        </style>
        </head><body><div class="slide">
        \(body)
        </div></body></html>
        """
    }

    // MARK: - Block structure

    /// A blank line separates blocks; lines inside one block stay together.
    static func blocks(from markdown: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private static func render(_ block: [String]) -> String {
        // A block made only of bullets becomes a list.
        if block.allSatisfy(isBullet) {
            let items = block
                .map { inline(stripBulletMarker(from: $0)) }
                .map { "<li>\($0)</li>" }
                .joined(separator: "\n")
            return "<ul>\n\(items)\n</ul>"
        }

        // A single line can be a heading or a rule.
        if block.count == 1 {
            let line = block[0]
            if line == "---" || line == "***" || line == "___" { return "<hr>" }
            for (marker, tag) in [("### ", "h3"), ("## ", "h2"), ("# ", "h1")] {
                if line.hasPrefix(marker) {
                    return "<\(tag)>\(inline(String(line.dropFirst(marker.count))))</\(tag)>"
                }
            }
        }

        // Otherwise a paragraph, keeping the author's line breaks.
        return "<p>" + block.map(inline).joined(separator: "<br>") + "</p>"
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
    }

    private static func stripBulletMarker(from line: String) -> String {
        String(line.dropFirst(2))
    }

    // MARK: - Inline markup

    /// Escapes first, then applies markup, so the text can never inject HTML.
    static func inline(_ text: String) -> String {
        var out = escapeHTML(text)

        // Park code spans so their contents are not treated as emphasis.
        var codeSpans: [String] = []
        out = replace(out, pattern: "`([^`\n]+)`") { match in
            codeSpans.append(match)
            return "\u{FFFC}\(codeSpans.count - 1)\u{FFFC}"
        }

        out = out.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\*([^*]+)\*"#, with: "<em>$1</em>", options: .regularExpression)
        // Underscores only at word boundaries, so snake_case survives intact.
        out = out.replacingOccurrences(
            of: #"(?<![A-Za-z0-9_])_([^_]+)_(?![A-Za-z0-9_])"#,
            with: "<em>$1</em>", options: .regularExpression)

        for (index, span) in codeSpans.enumerated() {
            out = out.replacingOccurrences(of: "\u{FFFC}\(index)\u{FFFC}", with: "<code>\(span)</code>")
        }
        return out
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Replaces every match of `pattern`, handing the first capture group to `transform`.
    private static func replace(_ text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let full = NSRange(text.startIndex..., in: text)
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text),
                  let group = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<range.lowerBound]
            result += transform(String(text[group]))
            last = range.upperBound
        }
        result += text[last...]
        return result
    }
}
