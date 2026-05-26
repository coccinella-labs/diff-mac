import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
        } detail: {
            WorkspaceView()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $store.mode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Button {
                    Task { await store.refreshCurrentMode() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh the current workspace")
                .accessibilityLabel("Refresh Current Workspace")
            }
        }
        .task {
            await store.loadAccount()
            await store.refreshCurrentMode()
        }
        .task(id: store.livePollingEnabled) {
            await store.runLivePollingLoop()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draftPendingDeletion: AIDraft?

    var body: some View {
        VStack(spacing: 0) {
            RepoHeaderView()
                .padding(14)

            Divider()

            HStack {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                TextField("Search", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search \(store.mode.title)")
                if isSearching {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
                    .help("Clear search")
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            HStack {
                Text(resultSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if store.mode == .pulls {
                Picker("State", selection: $store.pullFilter) {
                    ForEach(PullStateFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .onChange(of: store.pullFilter) {
                    Task { await store.loadPulls() }
                }
            }

            List {
                if !store.savedPulls.isEmpty {
                    Section("Saved") {
                        ForEach(store.savedPulls) { saved in
                            Button {
                                Task { await store.openSavedPull(saved) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("#\(saved.number) \(saved.title)")
                                        .lineLimit(1)
                                    Text("\(saved.owner)/\(saved.repo)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !store.recentRepos.isEmpty {
                    Section("Recent Repos") {
                        ForEach(store.recentRepos.prefix(5)) { recent in
                            Button("\(recent.owner)/\(recent.repo)") {
                                Task { await store.openRecentRepo(recent) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !store.aiDrafts.isEmpty {
                    Section("AI Drafts") {
                        ForEach(store.aiDrafts.prefix(8)) { draft in
                            HStack {
                                Button {
                                    store.openAIDraft(draft)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(draft.path)
                                            .lineLimit(1)
                                        Text("#\(draft.pullNumber) \(draft.pullTitle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    draftPendingDeletion = draft
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Delete AI Draft")
                                .accessibilityHint("Shows a confirmation before deleting this draft")
                                .help("Delete AI draft")
                            }
                        }
                    }
                }

                switch store.mode {
                case .pulls:
                    Section("Pull Requests") {
                        if store.filteredPulls.isEmpty {
                            EmptySearchRow(title: isSearching ? "No matching pull requests" : "No pull requests")
                        }
                        ForEach(store.filteredPulls) { pull in
                            PullRow(pull: pull, selected: store.selectedPull?.id == pull.id)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await store.selectPull(pull) } }
                        }
                        if store.hasMorePulls {
                            Button("Load More Pulls") {
                                Task { await store.loadMorePulls() }
                            }
                        }
                    }
                case .branches:
                    Section("Branches") {
                        if store.filteredBranches.isEmpty {
                            EmptySearchRow(title: isSearching ? "No matching branches" : "No branches")
                        }
                        ForEach(store.filteredBranches) { branch in
                            BranchRow(branch: branch, selected: store.selectedBranch?.name == branch.name)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await store.selectBranch(branch) } }
                        }
                        if store.hasMoreBranches {
                            Button("Load More Branches") {
                                Task { await store.loadMoreBranches() }
                            }
                        }
                    }
                case .code:
                    Section("Files") {
                        if store.filteredRepoFiles.isEmpty {
                            EmptySearchRow(title: isSearching ? "No matching files" : "No files")
                        }
                        ForEach(store.filteredRepoFiles) { file in
                            RepoFileRow(file: file, selected: store.selectedRepoFile?.path == file.path)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await store.selectRepoFile(file) } }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .confirmationDialog(
            "Delete AI Draft?",
            isPresented: Binding(
                get: { draftPendingDeletion != nil },
                set: { if !$0 { draftPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let draftPendingDeletion {
                Button("Delete Draft", role: .destructive) {
                    store.deleteAIDraft(draftPendingDeletion)
                    self.draftPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                draftPendingDeletion = nil
            }
        } message: {
            if let draftPendingDeletion {
                Text("\(draftPendingDeletion.path) for #\(draftPendingDeletion.pullNumber)")
            }
        }
    }

    private var isSearching: Bool {
        !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resultSummary: String {
        switch store.mode {
        case .pulls:
            return isSearching ? "\(store.filteredPulls.count) of \(store.pulls.count) pull requests" : "\(store.pulls.count) pull requests"
        case .branches:
            return isSearching ? "\(store.filteredBranches.count) of \(store.branches.count) branches" : "\(store.branches.count) branches"
        case .code:
            let files = store.repoFiles.filter { $0.type == "blob" }
            return isSearching ? "\(store.filteredRepoFiles.count) of \(files.count) files" : "\(files.count) files"
        }
    }
}

struct EmptySearchRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

struct RepoHeaderView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIFF")
                        .font(.title2.bold())
                    Text(store.repo.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let viewer = store.viewer {
                    Text(viewer.login)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.16), in: Capsule())
                } else {
                    Text("anonymous")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.16), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                TextField("Owner", text: Binding(
                    get: { store.repo.owner },
                    set: { store.repo.owner = $0 }
                ))
                TextField("Repo", text: Binding(
                    get: { store.repo.name },
                    set: { store.repo.name = $0 }
                ))
                Button("Apply") {
                    store.saveSettings()
                    Task { await store.refreshCurrentMode() }
                }
            }

            if store.mode == .code {
                HStack {
                    TextField("Ref", text: $store.repoRef)
                    Button("Load") {
                        store.saveSettings()
                        Task { await store.loadRepoTree() }
                    }
                }
            }
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView()

            Divider()

            switch store.mode {
            case .pulls:
                PullWorkspaceView()
            case .branches:
                BranchWorkspaceView()
            case .code:
                CodeWorkspaceView()
            }
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            if store.detailLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(store.errorMessage ?? store.statusMessage.ifEmpty("Ready"))
                .font(.callout)
                .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(1)
            Spacer()
            if store.errorMessage != nil {
                Button("Retry") {
                    Task { await store.refreshCurrentMode() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

struct PullWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if let snapshot = store.pullSnapshot {
            VStack(spacing: 0) {
                PullHeader(snapshot: snapshot)
                    .padding(18)

                Picker("Tab", selection: $store.activeTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

                Divider()

                switch store.activeTab {
                case .diff:
                    DiffFilesView(files: snapshot.files)
                case .discussion:
                    DiscussionView(snapshot: snapshot)
                case .checks:
                    ChecksView(checks: snapshot.checks)
                case .timeline:
                    TimelineView(snapshot: snapshot)
                }
            }
        } else {
            EmptyStateView(title: "No pull request selected", systemImage: "arrow.left", detail: "Choose a pull request from the sidebar or refresh the current repository.")
        }
    }
}

struct PullHeader: View {
    @EnvironmentObject private var store: AppStore
    let snapshot: PullSnapshot
    @State private var pendingAction: PullAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("#\(snapshot.pull.number)")
                            .foregroundStyle(.secondary)
                        Text(snapshot.pull.state.uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.14), in: Capsule())
                        if snapshot.pull.draft == true {
                            Text("DRAFT")
                                .font(.caption.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.orange.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(snapshot.pull.title)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text("by \(snapshot.pull.user.login) into \(snapshot.pull.base?.ref ?? "-") from \(snapshot.pull.head?.ref ?? "-")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url = snapshot.pull.htmlURL {
                    Link(destination: url) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                }
                Button {
                    store.toggleSavedSelectedPull()
                } label: {
                    Label("Save", systemImage: store.savedPulls.contains(where: { $0.owner == store.repo.owner && $0.repo == store.repo.name && $0.number == snapshot.pull.number }) ? "bookmark.fill" : "bookmark")
                }
            }

            DisclosureGroup("Manage pull request") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Title", text: $store.metadataTitle)
                    TextField("Labels, comma separated", text: $store.labelsDraft)
                    TextEditor(text: $store.metadataBody)
                        .font(.body)
                        .frame(minHeight: 90)
                        .border(.separator)
                    HStack {
                        Button("Save Metadata") {
                            Task { await store.savePullMetadata() }
                        }
                        Spacer()
                        Button("Update Branch") { pendingAction = .updateBranch }
                        Button("Delete Head", role: .destructive) { pendingAction = .deleteHead }
                        Button("Merge") { pendingAction = .merge }
                        Button("Squash") { pendingAction = .squash }
                        Button("Rebase") { pendingAction = .rebase }
                    }
                }
                .padding(.top, 8)
            }
        }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.confirmTitle, role: pendingAction.role) {
                    let action = pendingAction
                    self.pendingAction = nil
                    Task {
                        switch action {
                        case .updateBranch:
                            await store.updatePullBranch()
                        case .deleteHead:
                            await store.deletePullHeadBranch()
                        case .merge:
                            await store.mergePull(method: "merge")
                        case .squash:
                            await store.mergePull(method: "squash")
                        case .rebase:
                            await store.mergePull(method: "rebase")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        }
    }
}

enum PullAction: Identifiable {
    case updateBranch
    case deleteHead
    case merge
    case squash
    case rebase

    var id: String { title }

    var title: String {
        switch self {
        case .updateBranch: "Update branch?"
        case .deleteHead: "Delete head branch?"
        case .merge: "Merge pull request?"
        case .squash: "Squash pull request?"
        case .rebase: "Rebase pull request?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .updateBranch: "Update Branch"
        case .deleteHead: "Delete Head Branch"
        case .merge: "Merge"
        case .squash: "Squash"
        case .rebase: "Rebase"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .deleteHead:
            return .destructive
        default:
            return nil
        }
    }
}

struct DiffFilesView: View {
    let files: [ChangedFile]

    var body: some View {
        if files.isEmpty {
            EmptyStateView(title: "No changed files", systemImage: "doc.text", detail: "This pull request or comparison has no file changes to show.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(files) { file in
                        FileDiffCard(file: file)
                    }
                }
                .padding(18)
            }
        }
    }
}

struct FileDiffCard: View {
    let file: ChangedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                Text(file.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(file.status)
                    .foregroundStyle(.secondary)
                Text("+\(file.additions)")
                    .foregroundStyle(.green)
                Text("-\(file.deletions)")
                    .foregroundStyle(.red)
            }

            if let patch = file.patch, !patch.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(patch.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: String(line))
                    }
                }
                .padding(10)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No inline patch available.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }

    private var iconName: String {
        if file.status == "removed" { return "minus.square" }
        if file.status == "added" { return "plus.square" }
        return "doc.text"
    }
}

struct DiscussionView: View {
    @EnvironmentObject private var store: AppStore
    let snapshot: PullSnapshot

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let body = snapshot.pull.body, !body.isEmpty {
                        CommentCard(author: snapshot.pull.user.login, meta: "description", body: body)
                    }
                    ForEach(snapshot.comments) { comment in
                        CommentCard(author: comment.user.login, meta: comment.createdAt?.formatted() ?? "comment", body: comment.body)
                    }
                    ForEach(snapshot.reviewComments) { comment in
                        CommentCard(author: comment.user.login, meta: comment.path ?? "review comment", body: comment.body, code: comment.diffHunk)
                    }
                    ForEach(snapshot.reviews) { review in
                        CommentCard(author: review.user.login, meta: review.state, body: review.body ?? "")
                    }
                }
                .padding(18)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Write")
                    .font(.headline)
                TextEditor(text: $store.commentDraft)
                    .frame(minHeight: 120)
                    .border(.separator)
                Button("Post Comment") {
                    Task { await store.postComment() }
                }

                Divider()

                Text("Inline")
                    .font(.headline)
                TextField("Path", text: $store.inlineCommentPath)
                HStack {
                    TextField("Line", text: $store.inlineCommentLine)
                    Picker("Side", selection: $store.inlineCommentSide) {
                        Text("RIGHT").tag("RIGHT")
                        Text("LEFT").tag("LEFT")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                TextEditor(text: $store.inlineCommentDraft)
                    .frame(minHeight: 90)
                    .border(.separator)
                Button("Post Inline Comment") {
                    Task { await store.postInlineReviewComment() }
                }

                Divider()

                Text("Review")
                    .font(.headline)
                TextEditor(text: $store.reviewDraft)
                    .frame(minHeight: 120)
                    .border(.separator)
                HStack {
                    Button("Comment") { Task { await store.submitReview(event: "COMMENT") } }
                    Button("Approve") { Task { await store.submitReview(event: "APPROVE") } }
                    Button("Request Changes") { Task { await store.submitReview(event: "REQUEST_CHANGES") } }
                }

                Divider()

                Button("Draft Fix From Review Comment") {
                    Task { await store.draftFixFromFirstReviewComment() }
                }
            }
            .padding(18)
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
        }
    }
}

struct ChecksView: View {
    @EnvironmentObject private var store: AppStore
    let checks: [CheckRun]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(checks) { check in
                    CheckRunCard(check: check)
                }
            }
            .padding(18)
        }
    }
}

struct CheckRunCard: View {
    @EnvironmentObject private var store: AppStore
    let check: CheckRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: check.conclusion == "success" ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(check.conclusion == "success" ? .green : .secondary)
                Text(check.name)
                    .font(.headline)
                Spacer()
                Text(check.conclusion ?? check.status ?? "unknown")
                    .foregroundStyle(.secondary)
            }
            if let summary = check.output?.summary, !summary.isEmpty {
                MarkdownText(summary)
                    .foregroundStyle(.secondary)
            }
            if let text = check.output?.text, !text.isEmpty {
                DisclosureGroup("Output") {
                    MarkdownBlockText(text)
                        .padding(.top, 6)
                }
            }
            HStack {
                Button(store.checkAnnotations[check.id] == nil ? "Load Annotations" : "Reload Annotations") {
                    Task { await store.loadCheckAnnotations(for: check) }
                }
                if store.loadingCheckAnnotations.contains(check.id) {
                    ProgressView()
                        .controlSize(.small)
                }
                if let url = check.htmlURL {
                    Link("Open on GitHub", destination: url)
                }
            }

            if let annotations = store.checkAnnotations[check.id] {
                if annotations.isEmpty {
                    Text("No annotations.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(annotations) { annotation in
                            AnnotationRow(annotation: annotation)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

struct AnnotationRow: View {
    let annotation: CheckAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(annotation.annotationLevel.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(levelColor)
                Text(annotation.path)
                    .font(.system(.caption, design: .monospaced))
                if let start = annotation.startLine {
                    Text(":\(start)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let title = annotation.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(annotation.message)
                .textSelection(.enabled)
            if let raw = annotation.rawDetails, !raw.isEmpty {
                Text(raw)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(levelColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var levelColor: Color {
        switch annotation.annotationLevel.lowercased() {
        case "failure":
            return .red
        case "warning":
            return .orange
        default:
            return .blue
        }
    }
}

struct TimelineView: View {
    let snapshot: PullSnapshot

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(snapshot.timeline) { event in
                    CommentCard(
                        author: event.actor?.login ?? event.user?.login ?? "GitHub",
                        meta: event.event.replacingOccurrences(of: "_", with: " "),
                        body: event.body ?? event.commitID ?? event.state ?? ""
                    )
                }
                ForEach(snapshot.commits) { commit in
                    CommentCard(
                        author: commit.author?.login ?? commit.commit.author?.name ?? "commit",
                        meta: commit.sha.prefix(7).description,
                        body: commit.commit.message
                    )
                }
            }
            .padding(18)
        }
    }
}

struct BranchWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if let snapshot = store.branchSnapshot {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snapshot.branch.name)
                                .font(.title2.bold())
                            Text("Compared with \(snapshot.base) at \(snapshot.branch.commit.sha.prefix(7))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    DisclosureGroup("Branch and pull request actions") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("New branch name", text: $store.newBranchName)
                                Button("Create Branch") {
                                    Task { await store.createBranch() }
                                }
                            }

                            TextField("Pull title", text: $store.pullTitle)
                            TextField("Head branch", text: $store.pullHead)
                            TextField("Base branch", text: $store.pullBase)
                            TextEditor(text: $store.pullBody)
                                .frame(minHeight: 90)
                                .border(.separator)
                            Button("Open Pull Request") {
                                Task { await store.createPullRequest() }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(18)

                Divider()

                HSplitView {
                    DiffFilesView(files: snapshot.files)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(snapshot.commits) { commit in
                                CommentCard(
                                    author: commit.author?.login ?? commit.commit.author?.name ?? "commit",
                                    meta: commit.sha.prefix(7).description,
                                    body: commit.commit.message
                                )
                            }
                        }
                        .padding(18)
                    }
                    .frame(minWidth: 300)
                }
            }
        } else {
            EmptyStateView(title: "No branch selected", systemImage: "point.3.connected.trianglepath.dotted", detail: "Choose a branch from the sidebar to compare it with the default branch.")
        }
    }
}

struct CodeWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("New File", isOn: $store.createFileMode)
                    .toggleStyle(.switch)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Divider()

            if store.createFileMode {
                NewFileView()
            } else if let file = store.selectedRepoFile {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.path)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text(store.repo.displayName + " @ " + store.repoRef)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(file.sha.prefix(7))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(18)

                Divider()

                if store.repoFileIsLikelyBinary {
                    Label("This file contains control characters and may be binary. Editing is disabled to avoid corrupting it.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .padding(12)
                }
                if store.repoFileIsLarge {
                    Label("This file is large. Editing and committing are disabled in the built-in editor.", systemImage: "doc.zipper")
                        .foregroundStyle(.orange)
                        .padding(12)
                }

                CodeEditorView(text: $store.repoFileContent, path: file.path)
                    .disabled(store.repoFileIsLikelyBinary || store.repoFileIsLarge)

                Divider()

                if !store.conflictBlocks.isEmpty {
                    ConflictResolutionPanel(blocks: store.conflictBlocks)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    Divider()
                }

                HStack {
                    if store.isRepoFileDirty {
                        Text("Modified")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Button("Revert") {
                        store.revertRepoFileEdits()
                    }
                    .disabled(!store.isRepoFileDirty)
                    .help("Revert the editor to the last loaded file content")
                    TextField("Commit message", text: $store.commitMessage)
                        .accessibilityLabel("Commit Message")
                    Button("Load Base") {
                        Task { await store.loadConflictBaseForSelectedFile() }
                    }
                    .help("Load the base branch version for three-way conflict review")
                    Button("Commit File") {
                        Task { await store.commitRepoFile() }
                    }
                    .disabled(store.repoFileIsLikelyBinary || store.repoFileIsLarge || store.hasUnresolvedConflicts)
                    .help(store.hasUnresolvedConflicts ? "Resolve all conflict markers before committing" : "Commit the edited file")
                }
                .padding(14)

                if !store.conflictBaseContent.isEmpty {
                    Divider()
                    DisclosureGroup("Base version: \(store.conflictBaseRef)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Replace Editor With Base Version") {
                                store.replaceEditorWithConflictBase()
                            }
                            Text(store.conflictBaseContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        } else {
            EmptyStateView(title: "No repository file selected", systemImage: "doc.text.magnifyingglass", detail: "Choose a file from the sidebar, or turn on New File to create one.")
        }
        }
    }
}

struct ConflictResolutionPanel: View {
    @EnvironmentObject private var store: AppStore
    let blocks: [ConflictBlock]
    @State private var selectedIndex = 0
    @State private var choicesByBlockID: [Int: ConflictChoice] = [:]

    private var selectedBlock: ConflictBlock? {
        guard !blocks.isEmpty else { return nil }
        return blocks[min(selectedIndex, blocks.count - 1)]
    }

    private var selectedChoice: Binding<ConflictChoice> {
        Binding(
            get: {
                guard let selectedBlock else { return .ours }
                return choicesByBlockID[selectedBlock.id] ?? .ours
            },
            set: { choice in
                guard let selectedBlock else { return }
                choicesByBlockID[selectedBlock.id] = choice
            }
        )
    }

    var body: some View {
        DisclosureGroup("Conflict markers (\(blocks.count))") {
            VStack(alignment: .leading, spacing: 10) {
                if let block = selectedBlock {
                    HStack {
                        Text("Conflict \(min(selectedIndex, blocks.count - 1) + 1) of \(blocks.count): lines \(block.startLine)-\(block.endLine)")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            selectedIndex = max(selectedIndex - 1, 0)
                        } label: {
                            Label("Previous Conflict", systemImage: "chevron.up")
                        }
                        .disabled(selectedIndex == 0)
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        .help("Go to the previous conflict")

                        Button {
                            selectedIndex = min(selectedIndex + 1, blocks.count - 1)
                        } label: {
                            Label("Next Conflict", systemImage: "chevron.down")
                        }
                        .disabled(selectedIndex >= blocks.count - 1)
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                        .help("Go to the next conflict")
                    }
                    HStack {
                        Button("Accept Ours") {
                            store.resolveConflict(blockID: block.id, choice: .ours)
                        }
                        .keyboardShortcut("o", modifiers: [.command, .option])
                        .help("Resolve the selected conflict using the ours side")
                        Button("Accept Theirs") {
                            store.resolveConflict(blockID: block.id, choice: .theirs)
                        }
                        .keyboardShortcut("t", modifiers: [.command, .option])
                        .help("Resolve the selected conflict using the theirs side")
                        Button("Keep Both") {
                            store.resolveConflict(blockID: block.id, choice: .both)
                        }
                        .keyboardShortcut("b", modifiers: [.command, .option])
                        .help("Resolve the selected conflict by keeping both sides")
                        Divider()
                            .frame(height: 18)
                        Picker("Hunk Choice", selection: selectedChoice) {
                            Text("Ours").tag(ConflictChoice.ours)
                            Text("Theirs").tag(ConflictChoice.theirs)
                            Text("Both").tag(ConflictChoice.both)
                        }
                        .labelsHidden()
                        .accessibilityLabel("Reviewed Hunk Choice")
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        Button("Apply Reviewed") {
                            store.resolveConflicts(choicesByBlockID: choicesByBlockID)
                            choicesByBlockID = [:]
                        }
                        .disabled(choicesByBlockID.count != blocks.count)
                        .help(choicesByBlockID.count == blocks.count ? "Apply all reviewed hunk choices" : "Review every conflict before applying")
                        Button("Reset Review") {
                            choicesByBlockID = [:]
                        }
                        .disabled(choicesByBlockID.isEmpty)
                        .help("Clear staged hunk choices without changing the file")
                        Menu("Mark All") {
                            Button("Mark All Ours") {
                                markAllConflicts(.ours)
                            }
                            Button("Mark All Theirs") {
                                markAllConflicts(.theirs)
                            }
                            Button("Mark All Both") {
                                markAllConflicts(.both)
                            }
                        }
                        Menu("Resolve All") {
                            Button("Accept All Ours") {
                                store.resolveAllConflicts(choice: .ours)
                            }
                            Button("Accept All Theirs") {
                                store.resolveAllConflicts(choice: .theirs)
                            }
                            Button("Keep All Both") {
                                store.resolveAllConflicts(choice: .both)
                            }
                        }
                    }
                    HSplitView {
                        ConflictSide(title: "Ours", text: block.ours)
                        if !store.conflictBaseContent.isEmpty {
                            ConflictSide(
                                title: "Base: \(store.conflictBaseRef)",
                                text: EditorTextTools.lineRangePreview(
                                    store.conflictBaseContent,
                                    startLine: block.startLine,
                                    endLine: block.endLine
                                )
                            )
                        }
                        ConflictSide(title: "Theirs", text: block.theirs)
                    }
                    .frame(minHeight: 120)

                    ConflictSide(
                        title: "Resolved Preview: \(selectedChoice.wrappedValue.title)",
                        text: block.resolvedText(choice: selectedChoice.wrappedValue)
                    )
                    .frame(minHeight: 90, maxHeight: 160)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(choicesByBlockID.count == blocks.count ? "Ready to apply reviewed choices" : "\(choicesByBlockID.count) of \(blocks.count) reviewed")
                                .font(.caption)
                                .foregroundStyle(choicesByBlockID.count == blocks.count ? .green : .secondary)
                            Spacer()
                            if choicesByBlockID.count < blocks.count {
                                Text("\(blocks.count - choicesByBlockID.count) unreviewed")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        selectedIndex = index
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("\(index + 1)")
                                                .font(.caption.bold())
                                            Text("L\(item.startLine)-\(item.endLine)")
                                                .font(.caption)
                                            if let choice = choicesByBlockID[item.id] {
                                                Text(choice.title)
                                                    .font(.caption.bold())
                                            } else {
                                                Text("Open")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(index == selectedIndex ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .onChange(of: blocks.count) { _, count in
            selectedIndex = min(selectedIndex, max(count - 1, 0))
            choicesByBlockID = choicesByBlockID.filter { blockID, _ in
                blocks.contains { $0.id == blockID }
            }
        }
    }

    private func markAllConflicts(_ choice: ConflictChoice) {
        choicesByBlockID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, choice) })
    }
}

struct ConflictSide: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct NewFileView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create File")
                    .font(.title3.bold())
                TextField("Path", text: $store.newFilePath)
                if RepoPathValidator.isInvalid(store.newFilePath), !store.newFilePath.isEmpty {
                    Text("Use a relative file path without leading slash, trailing slash, duplicate slash, or '..'.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if FileSizePolicy.isLarge(store.newFileContent) {
                    Text("This new file is too large for the built-in editor.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Commit message", text: $store.newFileCommitMessage)
            }
            .padding(18)

            Divider()

            CodeEditorView(text: $store.newFileContent, path: store.newFilePath)

            Divider()

            HStack {
                Spacer()
                Button("Create File") {
                    Task { await store.createRepoFile() }
                }
                .disabled(RepoPathValidator.isInvalid(store.newFilePath) || FileSizePolicy.isLarge(store.newFileContent))
            }
            .padding(14)
        }
    }
}

struct CommentCard: View {
    let author: String
    let meta: String
    let text: String
    var code: String?

    init(author: String, meta: String, body: String, code: String? = nil) {
        self.author = author
        self.meta = meta
        self.text = body
        self.code = code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(author)
                    .font(.headline)
                Text(meta)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if !text.isEmpty {
                MarkdownText(text)
            }
            if let code, !code.isEmpty {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

struct MarkdownBlockText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

struct CodeEditorView: View {
    @Binding var text: String
    let path: String
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var goToLine = ""
    @State private var linePreview = ""
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find in file", text: $findText)
                        .textFieldStyle(.plain)
                    if !findText.isEmpty {
                        Text("\(matchCount) matches")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Preview", isOn: $showPreview)
                        .toggleStyle(.switch)
                }

                HStack {
                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                    Button("Replace All") {
                        text = EditorTextTools.replacing(text, find: findText, replacement: replaceText)
                    }
                    .disabled(findText.isEmpty)
                    Divider()
                    TextField("Line", text: $goToLine)
                        .frame(width: 72)
                        .textFieldStyle(.plain)
                    Button("Preview Line") {
                        linePreview = EditorTextTools.linePreview(text, line: Int(goToLine) ?? 0)
                    }
                    .disabled(goToLine.isEmpty)
                }
            }
            .padding(8)
            .background(.quaternary)

            if !linePreview.isEmpty {
                Text(linePreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.yellow.opacity(0.08))
            }

            if showPreview {
                ScrollView {
                    HighlightedCodeView(text: text, path: path)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(1...max(lineCount, 1), id: \.self) { line in
                                Text("\(line)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 19)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                    }
                    .frame(minWidth: 54, idealWidth: 62, maxWidth: 70)
                    .background(.black.opacity(0.04))

                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                }
            }
        }
    }

    private var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var matchCount: Int {
        guard !findText.isEmpty else { return 0 }
        return text.lowercased().components(separatedBy: findText.lowercased()).count - 1
    }
}

struct HighlightedCodeView: View {
    let text: String
    let path: String

    var body: some View {
        let highlightedLines = SyntaxHighlighter.highlightedLines(for: text, path: path)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(highlightedLines.enumerated()), id: \.offset) { index, tokens in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(attributedLine(tokens))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func attributedLine(_ tokens: [SyntaxToken]) -> AttributedString {
        var result = AttributedString()
        for token in tokens {
            var segment = AttributedString(token.text)
            switch token.kind {
            case .plain:
                break
            case .keyword:
                segment.foregroundColor = .blue
            case .string:
                segment.foregroundColor = .green
            case .number:
                segment.foregroundColor = .purple
            case .comment:
                segment.foregroundColor = .secondary
            case .markup:
                segment.foregroundColor = .orange
            case .diffAddition:
                segment.foregroundColor = .green
            case .diffDeletion:
                segment.foregroundColor = .red
            }
            result.append(segment)
        }
        return result
    }
}

struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.vertical, 1)
            .background(background)
    }

    private var foreground: Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return .primary
    }

    private var background: Color {
        if line.hasPrefix("+") { return .green.opacity(0.08) }
        if line.hasPrefix("-") { return .red.opacity(0.08) }
        if line.hasPrefix("@@") { return .blue.opacity(0.08) }
        return .clear
    }
}

struct PullRow: View {
    let pull: PullRequest
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("#\(pull.number)")
                    .foregroundStyle(.secondary)
                Text(pull.state)
                    .font(.caption)
                Spacer()
            }
            Text(pull.title)
                .font(.headline)
                .lineLimit(2)
            Text(pull.user.login)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BranchRow: View {
    let branch: Branch
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(branch.name)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(branch.commit.sha.prefix(7))
                    .font(.system(.caption, design: .monospaced))
                if branch.protected {
                    Text("protected")
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RepoFileRow: View {
    let file: RepoTreeItem
    let selected: Bool

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(file.path)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @State private var showingDiagnostics = false

    var body: some View {
        Form {
            Section("About") {
                Text("\(AppMetadata.name) \(AppMetadata.version) (\(AppMetadata.build))")
                    .foregroundStyle(.secondary)
                Button("Show Diagnostics") {
                    showingDiagnostics = true
                }
            }

            Section("Repository") {
                TextField("Owner", text: Binding(
                    get: { store.repo.owner },
                    set: { store.repo.owner = $0 }
                ))
                TextField("Name", text: Binding(
                    get: { store.repo.name },
                    set: { store.repo.name = $0 }
                ))
            }

            Section("GitHub") {
                TextField("OAuth Client ID", text: $store.githubOAuthClientID)
                TextField("OAuth Exchange Endpoint", text: $store.githubOAuthExchangeEndpoint)
                LabeledContent("Callback URL") {
                    Text(store.githubOAuthCallbackURL)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }
                if store.canStartGitHubBrowserOAuth {
                    Button("Open GitHub Browser Sign-In") {
                        if let url = store.prepareGitHubBrowserOAuthURL() {
                            openURL(url)
                        }
                    }
                } else if !store.githubOAuthExchangeEndpoint.isEmpty {
                    Text("Browser sign-in requires an HTTPS exchange endpoint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(store.isPollingDeviceOAuth ? "Waiting for GitHub..." : "Sign In With GitHub Device Code") {
                    Task { await store.startGitHubDeviceOAuth() }
                }
                if let url = store.deviceVerificationURL {
                    Link("Open GitHub Device Page", destination: url)
                }
                if !store.deviceUserCode.isEmpty {
                    Text(store.deviceUserCode)
                        .font(.system(.title3, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
                if !store.deviceOAuthMessage.isEmpty {
                    Text(store.deviceOAuthMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField("Token", text: $store.token)
                Text("Stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini") {
                SecureField("API Key", text: $store.geminiAPIKey)
            }

            Section("Supabase") {
                TextField("Project URL", text: $store.supabaseURL)
                SecureField("Anon Key", text: $store.supabaseAnonKey)
                SecureField("Access Token", text: $store.supabaseAccessToken)
                SecureField("Refresh Token", text: $store.supabaseRefreshToken)
                LabeledContent("Callback URL") {
                    Text(store.supabaseAuthCallbackURL)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }
                if let authURL = store.supabaseAuthorizeURL() {
                    Link("Open Supabase GitHub Sign-In", destination: authURL)
                }
                HStack {
                    Button("Refresh Session") {
                        Task { await store.refreshSupabaseSession() }
                    }
                    Button("Pull Preferences") {
                        Task { await store.pullSupabasePreferences() }
                    }
                    Button("Push Preferences") {
                        Task { await store.pushSupabasePreferences() }
                    }
                }
                if !store.supabaseSyncMessage.isEmpty {
                    Text(store.supabaseSyncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Uses the web app's public.user_preferences row. The Supabase callback must allow diffmac://supabase-auth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Live pull refresh", isOn: $store.livePollingEnabled)
                Stepper("Refresh every \(store.livePollingIntervalSeconds)s", value: $store.livePollingIntervalSeconds, in: 15...300, step: 15)
                Button("Save and Verify") {
                    store.saveSettings()
                    Task {
                        await store.loadAccount()
                        await store.refreshCurrentMode()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(snapshot: store.diagnosticsSnapshot)
                .frame(width: 560, height: 420)
        }
    }
}

struct DiagnosticsView: View {
    let snapshot: DiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.title2.bold())
                Spacer()
            }
            Text("Secrets are redacted.")
                .foregroundStyle(.secondary)
            Text(snapshot.redactedText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
