import Foundation
import Testing
@testable import RubberStampKit

@Suite("Search response parsing")
struct ParseSearchTests {
    let json = """
    {
      "total_count": 3,
      "items": [
        {"number": 7, "title": "Older", "html_url": "https://github.com/org/app/pull/7",
         "draft": false, "user": {"login": "alice"},
         "repository_url": "https://api.github.com/repos/org/app",
         "updated_at": "2026-11-01T10:00:00Z"},
        {"number": 12, "title": "Newest, draft", "html_url": "https://github.com/org/lib/pull/12",
         "draft": true, "user": {"login": "my-app[bot]"},
         "repository_url": "https://api.github.com/repos/org/lib",
         "updated_at": "2026-11-27T09:00:00Z"},
        {"number": 3, "title": "No draft field", "html_url": "https://github.com/x/y/pull/3",
         "user": {"login": "bob"},
         "repository_url": "https://api.github.com/repos/x/y",
         "updated_at": "2026-11-15T09:00:00Z"}
      ]
    }
    """

    @Test("Fields are mapped and sorted newest first")
    func mapsAndSorts() throws {
        let prs = try GitHub.parseSearch(Data(json.utf8))
        #expect(prs.map(\.number) == [12, 3, 7])
        let newest = try #require(prs.first)
        #expect(newest.repo == "org/lib")
        #expect(newest.author == "my-app[bot]")
        #expect(newest.isDraft)
        #expect(newest.id == "https://github.com/org/lib/pull/12")
    }

    @Test("Missing draft field means not a draft")
    func missingDraft() throws {
        let prs = try GitHub.parseSearch(Data(json.utf8))
        #expect(prs.first { $0.number == 3 }?.isDraft == false)
    }

    @Test("Empty result")
    func empty() throws {
        #expect(try GitHub.parseSearch(Data(#"{"total_count":0,"items":[]}"#.utf8)).isEmpty)
    }

    @Test("Malformed JSON throws")
    func malformed() {
        #expect(throws: (any Error).self) { try GitHub.parseSearch(Data("not json".utf8)) }
    }
}

@Suite("gh command lines")
struct ArgsTests {
    @Test("Search asks only for personal review requests on open PRs")
    func searchArgs() {
        let args = GitHub.reviewRequestArgs()
        #expect(args.contains("search/issues"))
        let q = try? #require(args.first { $0.hasPrefix("q=") })
        #expect(q?.contains("user-review-requested:@me") == true)
        #expect(q?.contains("is:open") == true)
        #expect(q?.contains("is:pr") == true)
    }

    @Test("Approve posts an APPROVE review to the right PR")
    func approveArgs() {
        let url = URL(string: "https://github.com/org/app/pull/42")!
        let p = PullRequest(id: url.absoluteString, repo: "org/app", number: 42, title: "t",
                            author: "a", url: url, isDraft: false, updatedAt: nil)
        #expect(GitHub.approveArgs(p) == ["api", "-X", "POST", "repos/org/app/pulls/42/reviews", "-f", "event=APPROVE"])
    }
}

/// Runs `GitHub.run` against a fake `gh` script, so no network or real login is involved.
@Suite("Running the CLI")
struct RunTests {
    func fakeGh(_ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("gh").path
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test("Returns stdout and passes the arguments through")
    func success() async throws {
        let gh = try fakeGh(#"echo "args:$*""#)
        let out = try await GitHub.run(["api", "user"], executable: gh)
        #expect(String(decoding: out, as: UTF8.self) == "args:api user\n")
    }

    @Test("Disables interactive prompts")
    func noPrompts() async throws {
        let gh = try fakeGh(#"echo "$GH_PROMPT_DISABLED""#)
        let out = try await GitHub.run([], executable: gh)
        #expect(String(decoding: out, as: UTF8.self) == "1\n")
    }

    @Test("Non-zero exit throws with stderr as the message")
    func failure() async throws {
        let gh = try fakeGh(#"echo "HTTP 422: Can not approve your own pull request" >&2; exit 1"#)
        await #expect(throws: GHError.failed("HTTP 422: Can not approve your own pull request")) {
            _ = try await GitHub.run(["api"], executable: gh)
        }
    }

    @Test("Missing gh throws notInstalled")
    func notInstalled() async {
        await #expect(throws: GHError.notInstalled) {
            _ = try await GitHub.run([], executable: nil)
        }
    }

    @Test("Large output does not deadlock")
    func largeOutput() async throws {
        let gh = try fakeGh("head -c 1000000 /dev/zero")
        let out = try await GitHub.run([], executable: gh)
        #expect(out.count == 1_000_000)
    }
}
