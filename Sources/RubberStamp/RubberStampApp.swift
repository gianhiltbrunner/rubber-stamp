import AppKit
import RubberStampKit
import SwiftUI

@main
struct RubberStampApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: model.mode == .auto ? "checkmark.seal.fill" : "checkmark.seal")
                if model.pendingCount > 0 { Text("\(model.pendingCount)") }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review requests").font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                Button { SettingsWindow.show(model: model) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Settings")
            }

            Picker("Mode", selection: $model.mode) {
                Text("Manual").tag(Mode.manual)
                Text("Auto-approve").tag(Mode.auto)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.mode == .auto {
                Text(model.hasAutoRules
                     ? "Approves requests matching the repo and author rules in Settings (drafts skipped)."
                     : "Approves every request, all repos and authors (drafts skipped).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if model.prs.isEmpty {
                Text("No open review requests.").foregroundStyle(.secondary)
            } else if model.prs.count <= 4 {
                prList
            } else {
                ScrollView { prList }.frame(height: 240)
            }

            if !model.log.isEmpty {
                Divider()
                Text("Recently approved").font(.caption.bold())
                ForEach(model.log.prefix(3)) { entry in
                    HStack {
                        Image(systemName: entry.automatic ? "bolt.fill" : "hand.thumbsup.fill")
                            .foregroundStyle(.secondary)
                        Text("\(entry.pr.repo)#\(entry.pr.number)").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(entry.date, style: .time).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                    .onTapGesture { NSWorkspace.shared.open(entry.pr.url) }
                }
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Divider()
            HStack {
                if let last = model.lastRefresh {
                    Text("Updated \(last, style: .time)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var prList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.prs) { pr in PRRow(pr: pr) }
        }
    }
}

struct PRRow: View {
    @EnvironmentObject var model: Model
    let pr: PullRequest

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title).lineLimit(2)
                Text("\(pr.repo)#\(pr.number) · \(pr.author)\(pr.isDraft ? " · draft" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button { NSWorkspace.shared.open(pr.url) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless)
                .help("Open in browser")
            Button("Approve") { Task { await model.approve(pr) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.approving.contains(pr.id))
        }
    }
}

/// Settings live in their own window so the menu panel stays short.
enum SettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show(model: Model) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let w = NSWindow(contentViewController: host)
            w.title = "Rubber Stamp Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                Task { @MainActor in model.tidyRules() }
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.crop.circle")
                Text(model.account.map { "Signed in as \($0) through the GitHub CLI (gh)" }
                     ?? "Not signed in. Run `gh auth login` in a terminal.")
            }
            .font(.callout)

            Picker("Check every", selection: $model.intervalMinutes) {
                ForEach([1, 2, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
            }
            .frame(width: 220)

            Text("Auto-approve repos").font(.callout.bold())
            TextField("e.g. my-org/*, !my-org/prod-deploy", text: $model.repoFilter, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.tidyRules() }
            Text("Comma-separated. `owner/*` or `owner/repo` allows, `!` excludes. Empty = all repos.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Auto-approve authors").font(.callout.bold())
            TextField("e.g. alice, bob, my-app[bot]", text: $model.authorFilter, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.tidyRules() }
            Text("GitHub logins of PR authors, comma-separated. `!` excludes. Empty = all authors.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
        }
        .padding(16)
        .frame(width: 420)
        .task { await model.loadAccount() }
    }
}
