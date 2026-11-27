import Foundation
import RubberStampKit
import ServiceManagement

enum Mode: String, CaseIterable, Identifiable {
    case manual, auto
    var id: String { rawValue }
}

struct ApprovalLogEntry: Identifiable {
    let id = UUID()
    let pr: PullRequest
    let automatic: Bool
    let date: Date
}

@MainActor
final class Model: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: Mode {
        didSet {
            defaults.set(mode.rawValue, forKey: "mode")
            if mode == .auto { Task { await refresh() } }
        }
    }
    @Published var intervalMinutes: Int {
        didSet {
            defaults.set(intervalMinutes, forKey: "intervalMinutes")
            schedule()
        }
    }
    /// Comma- or newline-separated repo rules for auto mode.
    /// `owner/repo` or `owner/*` allows, a leading `!` excludes. No allow rule = all repos.
    @Published var repoFilter: String {
        didSet { defaults.set(repoFilter, forKey: "repoFilter") }
    }
    /// Comma- or newline-separated GitHub logins for auto mode. A leading `!` excludes.
    /// No allow rule = all authors.
    @Published var authorFilter: String {
        didSet { defaults.set(authorFilter, forKey: "authorFilter") }
    }

    @Published private(set) var prs: [PullRequest] = []
    @Published private(set) var approving: Set<String> = []
    @Published private(set) var log: [ApprovalLogEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var account: String?

    func loadAccount() async {
        account = try? await GitHub.currentUser()
    }

    /// PRs whose automatic approval failed; not retried automatically until they leave the queue.
    private var autoFailed: Set<String> = []
    private var timer: Timer?

    init() {
        Self.migrateLegacySettings()
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .manual
        let interval = defaults.integer(forKey: "intervalMinutes")
        intervalMinutes = interval > 0 ? interval : 2
        repoFilter = Rules.normalise(defaults.string(forKey: "repoFilter") ?? "")
        authorFilter = Rules.normalise(defaults.string(forKey: "authorFilter") ?? "")
        schedule()
        Task { await refresh() }
    }

    /// Early builds used the bundle id `local.pr-approver`; carry their settings over once.
    private static func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "mode") == nil,
              let legacy = UserDefaults(suiteName: "local.pr-approver") else { return }
        for key in ["mode", "intervalMinutes", "repoFilter", "authorFilter"] {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    var pendingCount: Int { prs.count }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await GitHub.reviewRequests()
            prs = fetched
            lastError = nil
            lastRefresh = Date()
            autoFailed.formIntersection(fetched.map(\.id))
            if mode == .auto {
                for pr in fetched where autoApprovable(pr) {
                    await approve(pr, automatic: true)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func autoApprovable(_ pr: PullRequest) -> Bool {
        Rules.autoApprovable(pr, repoRules: repoFilter, authorRules: authorFilter, failed: autoFailed)
    }

    /// Called when a rule field is submitted or the Settings window closes.
    func tidyRules() {
        let repos = Rules.normalise(repoFilter), authors = Rules.normalise(authorFilter)
        if repos != repoFilter { repoFilter = repos }
        if authors != authorFilter { authorFilter = authors }
    }

    var hasAutoRules: Bool {
        !(repoFilter + authorFilter).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func approve(_ pr: PullRequest, automatic: Bool = false) async {
        guard !approving.contains(pr.id) else { return }
        approving.insert(pr.id)
        defer { approving.remove(pr.id) }
        do {
            try await GitHub.approve(pr)
            prs.removeAll { $0.id == pr.id }
            log.insert(ApprovalLogEntry(pr: pr, automatic: automatic, date: Date()), at: 0)
            if log.count > 20 { log.removeLast(log.count - 20) }
        } catch {
            if automatic { autoFailed.insert(pr.id) }
            lastError = "Approving \(pr.repo)#\(pr.number) failed: \(error.localizedDescription)"
        }
    }

    // MARK: Launch at login (works once the .app sits in /Applications)

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
