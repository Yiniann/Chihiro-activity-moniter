import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ActivityMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chihiro Activity").font(.headline)
                    HStack(spacing: 6) {
                        StatusDot(state: monitor.connectionState)
                        Text(monitor.isPaused ? "已暂停" : monitor.connectionState.title)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    monitor.togglePaused()
                } label: {
                    Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .help(monitor.isPaused ? "恢复监测" : "暂停监测")
            }
            .padding(16)

            Divider()

            if monitor.publicSlots.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: monitor.isPaused ? "pause.circle" : "eye.slash")
                        .foregroundStyle(.secondary)
                    Text(monitor.isPaused ? "没有状态正在上报" : "当前没有可公开状态")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(monitor.publicSlots) { slot in
                        PublicSlotRow(slot: slot)
                        if slot.id != monitor.publicSlots.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if let error = monitor.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(ChihiroPalette.amber)
                    .lineLimit(2)
                    .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("打开控制台", systemImage: "slider.horizontal.3")
                }
                .adaptiveGlassButtonStyle(prominent: true)
                .tint(ChihiroPalette.blue)

                Button {
                    monitor.reconnect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .adaptiveGlassButtonStyle()
                .help("重新连接")

                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless)
                    .help("退出")
            }
            .padding(12)
        }
        .frame(width: 360)
    }
}
