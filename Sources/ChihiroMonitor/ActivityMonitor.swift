import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var publicSlots: [PublicActivitySlot] = []
    @Published private(set) var events: [ActivityEvent]
    @Published private(set) var lastReportAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var localFrontmostApplication: ForegroundApplication?
    @Published var isPaused: Bool
    @Published var token: String
    @Published var settings: MonitorSettings {
        didSet {
            saveSettings()
            applyLaunchAtLogin()
            rebuildPublicSlots(sendIfChanged: true)
        }
    }

    private let store: ActivityStore
    private let keychain = KeychainStore()
    private let foregroundCollector = ForegroundApplicationCollector()
    private let mediaCollector = NowPlayingCollector()
    private let realtime = RealtimeClient()
    private var currentMedia: NowPlayingActivity?
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sequence: UInt64 = 0
    private var heartbeatInterval: TimeInterval = 30
    private var lastHeartbeatAt = Date.distantPast
    private var lastMediaPollAt = Date.distantPast
    private var isMediaPollInFlight = false
    private var lastDisconnectedEventAt = Date.distantPast

    init(store: ActivityStore = ActivityStore()) {
        self.store = store
        self.events = store.load().events
        self.token = keychain.readToken()
        self.isPaused = UserDefaults.standard.bool(forKey: "monitor.paused")
        if let data = UserDefaults.standard.data(forKey: "monitor.settings"),
           let value = try? JSONDecoder().decode(MonitorSettings.self, from: data) {
            self.settings = value
        } else {
            self.settings = .defaults
        }

        configureRealtimeCallbacks()
        configureCollectors()
        configureSystemObservers()
        record(.monitorStarted, detail: "Activity Agent 已开始运行")

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if !token.isEmpty { reconnect() }
    }

    var visibleForegroundTitle: String? {
        publicSlots.first(where: { $0.id == "foreground" })?.title
    }

    var mediaSlot: PublicActivitySlot? {
        publicSlots.first(where: { $0.id == "media" })
    }

    func reconnect() {
        do {
            try keychain.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            lastError = nil
            realtime.connect(endpoint: settings.endpoint, token: token)
        } catch {
            lastError = "无法保存 Token：\(error.localizedDescription)"
        }
    }

    func copyTokenToPasteboard() {
        guard !token.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    func togglePaused() {
        isPaused.toggle()
        UserDefaults.standard.set(isPaused, forKey: "monitor.paused")
        if isPaused {
            publicSlots = []
            record(.paused, detail: "已清除全部公开状态")
            sendSnapshot()
        } else {
            record(.resumed, detail: "重新开始采集白名单活动")
            refreshCollectors()
        }
    }

    func addCurrentApplicationToAllowlist() {
        guard let application = localFrontmostApplication,
              !settings.allowlistedApplications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else { return }
        settings.allowlistedApplications.append(
            AllowedApplication(bundleIdentifier: application.bundleIdentifier, title: application.localizedName)
        )
    }

    func addAllowlistedApplication(_ application: AllowedApplication) {
        guard !settings.allowlistedApplications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else { return }
        settings.allowlistedApplications.append(application)
    }

    func updateAllowlistedApplication(id: UUID, title: String) {
        guard let index = settings.allowlistedApplications.firstIndex(where: { $0.id == id }) else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        settings.allowlistedApplications[index].title = normalizedTitle
    }

    func removeAllowlistedApplications(at offsets: IndexSet) {
        settings.allowlistedApplications.remove(atOffsets: offsets)
    }

    func removeAllowlistedApplication(id: UUID) {
        settings.allowlistedApplications.removeAll { $0.id == id }
    }

    func clearEvents() {
        events = []
        persist()
    }

    private func configureRealtimeCallbacks() {
        realtime.onStateChange = { [weak self] state in
            guard let self else { return }
            let previous = self.connectionState
            self.connectionState = state
            if state == .disconnected, previous != .disconnected,
               Date().timeIntervalSince(self.lastDisconnectedEventAt) > 10 {
                self.lastDisconnectedEventAt = Date()
                self.record(.disconnected, detail: "等待自动重连")
            }
        }
        realtime.onReady = { [weak self] heartbeat, _ in
            guard let self else { return }
            self.heartbeatInterval = max(10, heartbeat)
            self.record(.connected, detail: "activity.v1 握手完成")
            self.sendSnapshot()
        }
        realtime.onError = { [weak self] message in
            self?.lastError = message
        }
    }

    private func configureCollectors() {
        foregroundCollector.onChange = { [weak self] application in
            guard let self else { return }
            self.localFrontmostApplication = application
            self.rebuildPublicSlots(sendIfChanged: true)
        }
        foregroundCollector.start()
        localFrontmostApplication = foregroundCollector.currentApplication
        refreshCollectors()
    }

    private func configureSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForInactivity() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterInactivity() }
        })
        let distributed = DistributedNotificationCenter.default()
        workspaceObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForInactivity() }
        })
        workspaceObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterInactivity() }
        })
    }

    private func tick() {
        let now = Date()
        if settings.mediaEnabled, now.timeIntervalSince(lastMediaPollAt) >= 8, !isPaused {
            pollMedia()
        }

        if connectionState == .connected, now.timeIntervalSince(lastHeartbeatAt) >= heartbeatInterval {
            sendHeartbeat()
        }
    }

    private func refreshCollectors() {
        localFrontmostApplication = foregroundCollector.currentApplication
        if settings.mediaEnabled, !isPaused {
            pollMedia()
        } else {
            currentMedia = nil
        }
        rebuildPublicSlots(sendIfChanged: true)
    }

    private func pollMedia() {
        guard !isMediaPollInFlight else { return }
        isMediaPollInFlight = true
        lastMediaPollAt = Date()

        Task { [weak self, mediaCollector] in
            let nextMedia = await mediaCollector.collect()
            guard let self else { return }
            self.isMediaPollInFlight = false
            guard self.settings.mediaEnabled, !self.isPaused else { return }
            if nextMedia != self.currentMedia {
                self.currentMedia = nextMedia
                self.rebuildPublicSlots(sendIfChanged: true)
            }
        }
    }

    private func rebuildPublicSlots(sendIfChanged: Bool) {
        let previous = publicSlots
        if isPaused {
            publicSlots = []
        } else {
            let policy = PublishPolicy(settings: settings)
            publicSlots = [
                policy.foregroundSlot(for: localFrontmostApplication),
                policy.mediaSlot(for: currentMedia)
            ].compactMap { $0 }
        }
        if sendIfChanged, previous != publicSlots, connectionState == .connected { sendSnapshot() }
    }

    private func sendSnapshot() {
        sequence += 1
        let message = AgentSnapshot(sequence: sequence, slots: publicSlots)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.realtime.send(message)
                self.lastReportAt = Date()
                self.lastError = nil
                self.record(
                    .snapshotSent,
                    detail: self.snapshotDetail(for: message),
                    sequence: message.sequence,
                    slots: message.slots
                )
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func sendHeartbeat() {
        sequence += 1
        lastHeartbeatAt = Date()
        let heartbeat = AgentHeartbeat(sequence: sequence)
        Task { [weak self] in
            do {
                try await self?.realtime.send(heartbeat)
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    private func prepareForInactivity() {
        let previous = publicSlots
        publicSlots = []
        if !previous.isEmpty, connectionState == .connected { sendSnapshot() }
        realtime.disconnect(reconnect: false)
    }

    private func resumeAfterInactivity() {
        refreshCollectors()
        reconnect()
    }

    private func snapshotDetail(for snapshot: AgentSnapshot) -> String {
        guard !snapshot.slots.isEmpty else { return "快照 #\(snapshot.sequence) · 空快照" }
        let values = snapshot.slots.map { slot in
            let label = switch slot.kind {
            case "music": "音乐"
            case "video": "视频"
            case "media": "媒体"
            default: "应用"
            }
            return "\(label)：\(slot.title)"
        }
        return "快照 #\(snapshot.sequence) · " + values.joined(separator: "；")
    }

    private func record(
        _ kind: ActivityEvent.Kind,
        detail: String,
        sequence: UInt64? = nil,
        slots: [PublicActivitySlot]? = nil
    ) {
        events.insert(
            ActivityEvent(kind: kind, detail: detail, sequence: sequence, slots: slots),
            at: 0
        )
        if events.count > 100 { events = Array(events.prefix(100)) }
        persist()
    }

    private func persist() {
        try? store.save(PersistedActivity(events: events))
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "monitor.settings")
    }

    private func applyLaunchAtLogin() {
        if settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }
}
