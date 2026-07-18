import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ActivityMonitor

    var body: some View {
        Form {
            Section("WebSocket") {
                TextField(
                    "WebSocket 地址",
                    text: $monitor.settings.endpoint,
                    prompt: Text("wss://example.com/realtime/activity/agent")
                )
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    SecureField(
                        "Agent Token",
                        text: $monitor.token,
                        prompt: Text("从 Chihiro 后台复制")
                    )
                        .textFieldStyle(.roundedBorder)
                    Button {
                        monitor.copyTokenToPasteboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .adaptiveGlassButtonStyle()
                    .disabled(monitor.token.isEmpty)
                    .help("复制 Agent Token")
                }
                HStack {
                    Label(monitor.connectionState.title, systemImage: "circle.fill")
                        .foregroundStyle(monitor.connectionState == .connected ? ChihiroPalette.green : .secondary)
                    Spacer()
                    Button("连接") { monitor.reconnect() }
                        .adaptiveGlassButtonStyle(prominent: true)
                        .tint(ChihiroPalette.blue)
                }
            }

            Section("Now Playing") {
                Toggle("发布系统 Now Playing", isOn: $monitor.settings.mediaEnabled)
                Toggle("发布媒体标题", isOn: $monitor.settings.publishTrackTitle)
                    .disabled(!monitor.settings.mediaEnabled)
                Toggle("发布创作者", isOn: $monitor.settings.publishArtist)
                    .disabled(!monitor.settings.mediaEnabled || !monitor.settings.publishTrackTitle)
                Toggle("发布播放器来源", isOn: $monitor.settings.publishSourceApplication)
                    .disabled(!monitor.settings.mediaEnabled)
            }

            Section("系统") {
                Toggle("登录时启动", isOn: $monitor.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

struct AllowlistView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var showingAddSheet = false
    @State private var deletionCandidate: AllowedApplication?
    @State private var editingApplication: AllowedApplication?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("应用白名单").font(.title2.weight(.semibold))
                    Text("只有这里列出的前台应用可以离开这台 Mac").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { monitor.addCurrentApplicationToAllowlist() } label: {
                    Label("添加当前应用", systemImage: "scope")
                }
                .adaptiveGlassButtonStyle()
                .disabled(monitor.localFrontmostApplication == nil)
                Button { showingAddSheet = true } label: {
                    Label("添加", systemImage: "plus")
                }
                .adaptiveGlassButtonStyle(prominent: true)
                .tint(ChihiroPalette.blue)
            }

            if monitor.settings.allowlistedApplications.isEmpty {
                ContentUnavailableView("白名单为空", systemImage: "checkmark.shield", description: Text("当前不会上报任何前台应用"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(monitor.settings.allowlistedApplications) { application in
                        HStack(spacing: 12) {
                            applicationIcon(for: application)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(application.title).font(.body.weight(.medium))
                                Text(application.bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editingApplication = application
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("修改公开信息")
                            Button {
                                deletionCandidate = application
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("从白名单移除")
                        }
                        .padding(.vertical, 5)
                    }
                    .onDelete(perform: monitor.removeAllowlistedApplications)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChihiroPalette.border))
            }
        }
        .padding(28)
        .sheet(isPresented: $showingAddSheet) {
            AddApplicationSheet()
                .environmentObject(monitor)
        }
        .sheet(item: $editingApplication) { application in
            EditApplicationSheet(application: application) { title in
                monitor.updateAllowlistedApplication(id: application.id, title: title)
                editingApplication = nil
            }
        }
        .confirmationDialog(
            "从白名单移除 \(deletionCandidate?.title ?? "此应用")？",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            )
        ) {
            Button("移除", role: .destructive) {
                guard let application = deletionCandidate else { return }
                monitor.removeAllowlistedApplication(id: application.id)
                deletionCandidate = nil
            }
            Button("取消", role: .cancel) {
                deletionCandidate = nil
            }
        }
    }

    @ViewBuilder
    private func applicationIcon(for application: AllowedApplication) -> some View {
        if let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier
        ) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "macwindow")
                .foregroundStyle(ChihiroPalette.blue)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }
}

private struct EditApplicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let application: AllowedApplication
    let onSave: (String) -> Void
    @State private var title: String

    init(application: AllowedApplication, onSave: @escaping (String) -> Void) {
        self.application = application
        self.onSave = onSave
        _title = State(initialValue: application.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改公开信息")
                .font(.title2.weight(.semibold))

            Form {
                LabeledContent("Bundle ID") {
                    Text(application.bundleIdentifier)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                TextField("公开名称", text: $title)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(title)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct AddApplicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var applications: [InstalledApplicationOption] = []
    @State private var searchText = ""

    private var filteredApplications: [InstalledApplicationOption] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已安装的应用")
                        .font(.title2.weight(.semibold))
                    Text("选择允许公开的应用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refreshApplications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .adaptiveGlassButtonStyle()
                .help("刷新应用列表")
            }

            TextField("搜索应用或 Bundle ID", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredApplications.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "没有可添加的应用" : "没有匹配的应用",
                    systemImage: "app.dashed"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApplications) { application in
                    HStack(spacing: 12) {
                        applicationIcon(application.icon)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(application.name)
                                .font(.body.weight(.medium))
                            Text(application.bundleIdentifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if isAllowlisted(application) {
                            Label("已添加", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(ChihiroPalette.green)
                        } else {
                            Button {
                                monitor.addAllowlistedApplication(
                                    AllowedApplication(
                                        bundleIdentifier: application.bundleIdentifier,
                                        title: application.name
                                    )
                                )
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .help("添加到白名单")
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChihiroPalette.border))
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                .adaptiveGlassButtonStyle(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 540, height: 520)
        .onAppear(perform: refreshApplications)
    }

    private func isAllowlisted(_ application: InstalledApplicationOption) -> Bool {
        monitor.settings.allowlistedApplications.contains {
            $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
        }
    }

    private func refreshApplications() {
        let fileManager = FileManager.default
        let domains: [FileManager.SearchPathDomainMask] = [
            .userDomainMask,
            .localDomainMask,
            .systemDomainMask
        ]
        var seenBundleIdentifiers = Set<String>()
        var installedApplications: [InstalledApplicationOption] = []

        for domain in domains {
            guard let directory = fileManager.urls(for: .applicationDirectory, in: domain).first,
                  let enumerator = fileManager.enumerator(
                      at: directory,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }

            while let applicationURL = enumerator.nextObject() as? URL {
                guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                enumerator.skipDescendants()

                guard let bundle = Bundle(url: applicationURL),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      seenBundleIdentifiers.insert(bundleIdentifier.lowercased()).inserted else {
                    continue
                }

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? applicationURL.deletingPathExtension().lastPathComponent
                installedApplications.append(
                    InstalledApplicationOption(
                        bundleIdentifier: bundleIdentifier,
                        name: name,
                        icon: NSWorkspace.shared.icon(forFile: applicationURL.path)
                    )
                )
            }
        }

        applications = installedApplications.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func applicationIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "app")
                .foregroundStyle(ChihiroPalette.blue)
                .frame(width: 32, height: 32)
        }
    }
}

private struct InstalledApplicationOption: Identifiable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
}
