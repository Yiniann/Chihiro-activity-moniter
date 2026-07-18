import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case allowlist = "应用白名单"
    case activity = "上报记录"
    case connection = "WebSocket"
    case nowPlaying = "Now Playing"
    case general = "通用"

    var id: String { rawValue }

    static let monitoring: [DashboardSection] = [.overview, .allowlist, .activity]
    static let settings: [DashboardSection] = [.connection, .nowPlaying, .general]

    var symbol: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .allowlist: "checkmark.shield"
        case .activity: "arrow.up.arrow.down"
        case .connection: "network"
        case .nowPlaying: "play.square.stack"
        case .general: "gearshape"
        }
    }
}

struct DashboardShellView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @State private var selection: DashboardSection = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                DashboardIdentityHeader()
                Divider()
                List(selection: $selection) {
                    Section("监测") {
                        ForEach(DashboardSection.monitoring) { section in
                            Label(section.rawValue, systemImage: section.symbol)
                                .tag(section)
                        }
                    }
                    Section("设置") {
                        ForEach(DashboardSection.settings) { section in
                            Label(section.rawValue, systemImage: section.symbol)
                                .tag(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            selection = .connection
                        } label: {
                            HStack(spacing: 9) {
                                StatusDot(state: monitor.connectionState)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(monitor.isPaused ? "已暂停" : monitor.connectionState.title)
                                        .font(.caption.weight(.medium))
                                    Text("Agent · activity.v1")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .help("打开 WebSocket 设置")
                    }
                    .background(.bar)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            detail
                .environmentObject(monitor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.rawValue)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            monitor.reconnect()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("重新连接")

                        Button {
                            monitor.togglePaused()
                        } label: {
                            Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill")
                        }
                        .help(monitor.isPaused ? "恢复监测" : "暂停监测")
                    }
                }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview: OverviewView()
        case .allowlist: AllowlistView()
        case .activity: ActivityHistoryView()
        case .connection: ConnectionSettingsView()
        case .nowPlaying: NowPlayingSettingsView()
        case .general: GeneralSettingsView()
        }
    }
}

private struct DashboardIdentityHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            ActivityMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("Chihiro Monitor")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Mac Activity Agent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var monitor: ActivityMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("活动概览")
                        .font(.title2.weight(.semibold))
                    Text("Mac 本地筛选后的公开状态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 130), spacing: 14), count: 4),
                    spacing: 14
                ) {
                    MetricTile(title: "连接状态", value: monitor.connectionState.title, detail: "WSS", symbol: "link", tint: ChihiroPalette.green)
                    MetricTile(title: "公开状态", value: "\(monitor.publicSlots.count)", detail: "槽位", symbol: "eye", tint: ChihiroPalette.blue)
                    MetricTile(title: "应用白名单", value: "\(monitor.settings.allowlistedApplications.count)", detail: "本地", symbol: "checkmark.shield", tint: ChihiroPalette.amber)
                    MetricTile(title: "最近上报", value: monitor.lastReportAt?.formatted(date: .omitted, time: .shortened) ?? "尚未", detail: "快照", symbol: "arrow.up.circle", tint: .purple)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前公开状态").font(.headline)
                        if monitor.publicSlots.isEmpty {
                            ContentUnavailableView(
                                "没有公开状态",
                                systemImage: "eye.slash",
                                description: Text("白名单应用成为前台或音乐播放后会显示在这里")
                            )
                            .frame(height: 220)
                        } else {
                            ForEach(monitor.publicSlots) { slot in
                                PublicSlotRow(slot: slot)
                                if slot.id != monitor.publicSlots.last?.id { Divider() }
                            }
                            Spacer(minLength: 100)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
                    .adaptivePanel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近事件").font(.headline)
                        ForEach(monitor.events.prefix(4)) { event in
                            EventRow(event: event)
                            if event.id != monitor.events.prefix(4).last?.id { Divider() }
                        }
                    }
                    .padding(18)
                    .frame(width: 320, alignment: .topLeading)
                    .frame(minHeight: 270, alignment: .topLeading)
                    .adaptivePanel()
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ActivityHistoryView: View {
    @EnvironmentObject private var monitor: ActivityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("上报记录").font(.title2.weight(.semibold))
                    Text("仅记录连接与公开快照事件").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("清除记录", role: .destructive) { monitor.clearEvents() }
                    .adaptiveGlassButtonStyle()
            }
            List(monitor.events) { event in
                EventRow(event: event, showsSnapshotDetails: true)
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChihiroPalette.border))
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
