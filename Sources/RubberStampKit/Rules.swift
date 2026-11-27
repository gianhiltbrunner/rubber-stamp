import Foundation

/// Allow/exclude rules typed into Settings.
public enum Rules {
    /// Tidies typed or pasted rules into one `a, b, c` line: splits on commas and line
    /// breaks, trims each rule and drops empty ones.
    public static func normalise(_ text: String) -> String {
        text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Rules are comma/newline separated and case-insensitive; `!x` excludes, anything else
    /// allows. No allow rules = everything not excluded. With `wildcard`, `owner/*` matches
    /// every repo of that owner.
    public static func matches(_ value: String, rules text: String, wildcard: Bool) -> Bool {
        let rules = text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        let value = value.lowercased()
        func hit(_ pattern: String) -> Bool {
            wildcard && pattern.hasSuffix("/*") ? value.hasPrefix(String(pattern.dropLast())) : value == pattern
        }
        let excludes = rules.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
        let allows = rules.filter { !$0.hasPrefix("!") }
        if excludes.contains(where: hit) { return false }
        return allows.isEmpty || allows.contains(where: hit)
    }

    /// Whether auto mode may approve `pr`: not a draft, not failed before, and allowed by
    /// both the repo and the author rules.
    public static func autoApprovable(_ pr: PullRequest, repoRules: String, authorRules: String,
                                      failed: Set<String> = []) -> Bool {
        !pr.isDraft && !failed.contains(pr.id)
            && matches(pr.repo, rules: repoRules, wildcard: true)
            && matches(pr.author, rules: authorRules, wildcard: false)
    }
}
