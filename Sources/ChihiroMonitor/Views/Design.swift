import SwiftUI

enum ChihiroPalette {
    static let blue = Color(red: 0.18, green: 0.42, blue: 0.93)
    static let green = Color(red: 0.14, green: 0.67, blue: 0.42)
    static let amber = Color(red: 0.93, green: 0.58, blue: 0.12)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.09)
}

extension View {
    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func adaptivePanel() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.45)))
        } else {
            self
                .background(ChihiroPalette.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChihiroPalette.border))
        }
    }
}

struct ActivityMark: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(
                    .regular.tint(ChihiroPalette.blue),
                    in: RoundedRectangle(cornerRadius: 9)
                )
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(ChihiroPalette.blue)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "waveform")
                        .foregroundStyle(.white)
                        .fontWeight(.bold)
                )
        }
    }
}

struct StatusDot: View {
    let state: ConnectionState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(state == .connected ? 0.45 : 0), radius: 4)
            .accessibilityLabel(state.title)
    }

    private var color: Color {
        switch state {
        case .connected: ChihiroPalette.green
        case .connecting: ChihiroPalette.amber
        case .disconnected: .secondary.opacity(0.5)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptivePanel()
    }
}

struct PublicSlotRow: View {
    let slot: PublicActivitySlot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(detailText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(slot.id == "media" ? "媒体" : "应用")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var symbol: String {
        switch slot.kind {
        case "music": "music.note"
        case "video": "play.rectangle"
        case "media": "play.circle"
        default: "macwindow"
        }
    }

    private var tint: Color {
        switch slot.kind {
        case "music": ChihiroPalette.amber
        case "video": .red
        default: ChihiroPalette.blue
        }
    }

    private var detailText: String {
        let values = [slot.subtitle, slot.source]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        if !values.isEmpty { return values.joined(separator: " · ") }
        return slot.id == "media" ? "正在播放" : "前台应用"
    }
}

struct EventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(event.kind == .connected ? ChihiroPalette.green : ChihiroPalette.blue)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.title).font(.subheadline.weight(.medium))
                Text(event.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(event.timestamp, style: .relative).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}
