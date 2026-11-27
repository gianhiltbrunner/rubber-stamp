import Foundation
import Testing
@testable import RubberStampKit

func pr(repo: String = "org/app", author: String = "alice", draft: Bool = false, number: Int = 1) -> PullRequest {
    let url = URL(string: "https://github.com/\(repo)/pull/\(number)")!
    return PullRequest(id: url.absoluteString, repo: repo, number: number, title: "t",
                       author: author, url: url, isDraft: draft, updatedAt: nil)
}

@Suite("Rule matching")
struct RuleMatchingTests {
    @Test("Empty rules allow everything")
    func emptyAllowsAll() {
        #expect(Rules.matches("org/app", rules: "", wildcard: true))
        #expect(Rules.matches("org/app", rules: " , \n ", wildcard: true))
    }

    @Test("Exact repo allow")
    func exactRepo() {
        #expect(Rules.matches("org/app", rules: "org/app", wildcard: true))
        #expect(!Rules.matches("org/other", rules: "org/app", wildcard: true))
    }

    @Test("owner/* allows every repo of that owner, and only that owner")
    func ownerWildcard() {
        #expect(Rules.matches("org/app", rules: "org/*", wildcard: true))
        #expect(!Rules.matches("other/app", rules: "org/*", wildcard: true))
        #expect(!Rules.matches("org-two/app", rules: "org/*", wildcard: true))
    }

    @Test("Exclude wins over allow")
    func excludeWins() {
        #expect(!Rules.matches("org/prod", rules: "org/*, !org/prod", wildcard: true))
        #expect(Rules.matches("org/dev", rules: "org/*, !org/prod", wildcard: true))
    }

    @Test("Only excludes = everything else allowed")
    func onlyExcludes() {
        #expect(Rules.matches("org/dev", rules: "!org/prod", wildcard: true))
        #expect(!Rules.matches("org/prod", rules: "!org/prod", wildcard: true))
    }

    @Test("Case-insensitive, whitespace and newlines tolerated")
    func normalisation() {
        #expect(Rules.matches("Org/App", rules: "  org/app  ", wildcard: true))
        #expect(Rules.matches("org/b", rules: "org/a\norg/b", wildcard: true))
        #expect(Rules.matches("Alice", rules: "bob,\nALICE", wildcard: false))
    }

    @Test("Without wildcard, `/*` is literal")
    func noWildcardForAuthors() {
        #expect(!Rules.matches("alice", rules: "ali/*", wildcard: false))
    }

    @Test("Bot logins match verbatim")
    func botLogins() {
        #expect(Rules.matches("my-app[bot]", rules: "my-app[bot]", wildcard: false))
        #expect(!Rules.matches("my-app", rules: "my-app[bot]", wildcard: false))
    }
}

@Suite("Rule tidying")
struct NormaliseTests {
    @Test("Pasted trailing line break is removed")
    func trailingNewline() {
        #expect(Rules.normalise("Altishofer\n") == "Altishofer")
    }

    @Test("Line breaks, blanks and stray commas become one clean list")
    func mixed() {
        #expect(Rules.normalise("  alice\n\nbob ,, !mallory , ") == "alice, bob, !mallory")
    }

    @Test("Empty stays empty")
    func empty() {
        #expect(Rules.normalise(" \n , ") == "")
    }

    @Test("Tidying never changes what matches")
    func sameMeaning() {
        let raw = "org/*\n !org/prod ,"
        for repo in ["org/app", "org/prod", "other/x"] {
            #expect(Rules.matches(repo, rules: raw, wildcard: true)
                    == Rules.matches(repo, rules: Rules.normalise(raw), wildcard: true))
        }
    }
}

@Suite("Auto-approve policy")
struct AutoApproveTests {
    @Test("Plain PR with no rules is approved")
    func defaultApproves() {
        #expect(Rules.autoApprovable(pr(), repoRules: "", authorRules: ""))
    }

    @Test("Drafts are never auto-approved")
    func draftsSkipped() {
        #expect(!Rules.autoApprovable(pr(draft: true), repoRules: "", authorRules: ""))
    }

    @Test("Previously failed PRs are not retried")
    func failedSkipped() {
        let p = pr()
        #expect(!Rules.autoApprovable(p, repoRules: "", authorRules: "", failed: [p.id]))
    }

    @Test("Both repo and author rules must pass")
    func bothRulesApply() {
        let rules = (repo: "org/*", author: "alice, bob")
        #expect(Rules.autoApprovable(pr(repo: "org/app", author: "alice"), repoRules: rules.repo, authorRules: rules.author))
        #expect(!Rules.autoApprovable(pr(repo: "org/app", author: "mallory"), repoRules: rules.repo, authorRules: rules.author))
        #expect(!Rules.autoApprovable(pr(repo: "other/app", author: "alice"), repoRules: rules.repo, authorRules: rules.author))
    }

    @Test("Excluded author is skipped, everyone else approved")
    func excludedAuthor() {
        #expect(!Rules.autoApprovable(pr(author: "mallory"), repoRules: "", authorRules: "!mallory"))
        #expect(Rules.autoApprovable(pr(author: "alice"), repoRules: "", authorRules: "!mallory"))
    }
}
