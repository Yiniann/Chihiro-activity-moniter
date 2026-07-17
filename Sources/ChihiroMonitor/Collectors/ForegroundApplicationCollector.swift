import AppKit
import Foundation

@MainActor
final class ForegroundApplicationCollector {
    private var observer: NSObjectProtocol?
    private(set) var currentApplication: ForegroundApplication?
    var onChange: ((ForegroundApplication?) -> Void)?

    func start() {
        stop()
        capture(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.capture(application) }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func capture(_ application: NSRunningApplication?) {
        guard application?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard let bundleIdentifier = application?.bundleIdentifier,
              let localizedName = application?.localizedName else {
            currentApplication = nil
            onChange?(nil)
            return
        }

        let value = ForegroundApplication(bundleIdentifier: bundleIdentifier, localizedName: localizedName)
        guard value != currentApplication else { return }
        currentApplication = value
        onChange?(value)
    }
}
